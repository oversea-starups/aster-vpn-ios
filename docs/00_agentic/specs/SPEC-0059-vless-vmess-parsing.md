# SPEC-0059 — VLESS/VMess/AnyTLS Subscription Parsing

> Updated: 2026-09-01  
> Status: implemented and build/unit-bundle verified; production feed/device verification pending

## Input contract

- Accept UTF-8 subscription body up to 1 MiB.
- Body may be newline-delimited `vless://`, `vmess://` or secure `anytls://` entries or Base64 encoding of that text.
- Ignore blank/comment lines and unsupported protocols; install fails if no safe supported node remains.
- Parse at most 200 nodes. Extra, duplicate or invalid entries increase `discardedEntryCount` and never enter the catalog.

## VLESS

- URI form: `vless://uuid@host:port?...#Display%20Name`.
- Required: valid UUID, host, port, `encryption=none`, and `security=tls|reality`.
- New `security=none` VLESS entries are rejected because VLESS alone does not encrypt the transport and conflicts with the product's public-network protection promise.
- `allowInsecure` / `insecure` truthy values are rejected.
- Supported transports: `tcp`, `ws`/`websocket`, `grpc`.
- TLS: `sni`/`servername` falls back to host; optional uTLS `fp`.
- Reality: requires `pbk`; supports `sid`, `sni`, `fp` and `flow`.
- WebSocket: normalized path and optional `Host` header.
- gRPC: normalized `serviceName` / `service_name` / path field.

## VMess

- URI form: `vmess://base64(JSON)`; decoded JSON is bounded to 64 KiB.
- Required: `add`, `port`, valid `id`; supported `net` values match the transport whitelist.
- Supports `ps`, `aid`, `scy`, `host`, `path`, `tls`, `sni`, `fp`.
- TLS values are empty/`none` or `tls`; truthy `allowInsecure` is rejected.
- VMess without TLS is accepted only when VMess security is not `none`/`zero`; plaintext combinations are rejected. Deployment policy may further require TLS at the feed.

## AnyTLS

- URI form: `anytls://password@host:port?security=tls&sni=...&fp=...&alpn=h2,http/1.1#Display%20Name`.
- Required: non-empty password, host, port and `security=tls`. Passwords are stored in the dedicated AnyTLS credential field rather than the UUID field.
- Optional: `sni`/`servername`, uTLS `fp` and comma-separated `alpn` values. AnyTLS uses TCP transport.
- `allowInsecure` / `insecure` truthy values and `security=none|zero` are rejected; AnyTLS without TLS is never admitted.

## Canonical identity and validation

- Node ID is `node-` plus a truncated SHA-256 of normalized connection fields; display name is excluded so renaming does not break selection.
- IDs and logs never expose UUID/token.
- Duplicate query keys are rejected to avoid ambiguous interpretation.
- Every parsed `VPNNode` and embedded `TunnelConfiguration` passes model validation before installation.
- Unsupported/unsafe entries cannot overwrite last-known-good state; a catalog update is installed only when at least one safe node remains.

## Compatibility

- `TunnelConfiguration` schema v2 encodes VLESS/VMess/AnyTLS and transport-specific fields, including AnyTLS password and TLS ALPN.
- Schema v1 tunnel files continue decoding as VLESS-compatible current configs.
- Legacy current config preservation is separate from subscription admission: an existing owner-verified config is not silently deleted, while new insecure VLESS feed entries remain rejected.

## Verification

- Parser tests cover VLESS TLS/WebSocket, VLESS Reality/gRPC, Base64 VMess, secure AnyTLS password entries, unsupported entries, insecure flags, plaintext VLESS/AnyTLS rejection and deterministic deduplication.
- Builder tests cover schema-v1 migration, VMess output, AnyTLS password/TLS ALPN output, Reality/gRPC and bundled Libbox validation with an explicit uTLS fingerprint. Parser support alone is insufficient: the bundled Libbox must retain `with_utls`, and the arm64 regression must execute before release.
- Production acceptance additionally requires a controlled feed, live refresh/rollback and real-device line-switch matrix.
