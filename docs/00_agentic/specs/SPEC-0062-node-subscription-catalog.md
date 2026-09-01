# SPEC-0062 — Remote Node Catalog and Locations

> Confirmed: 2026-08-28  
> Status: implemented and build/unit-bundle verified; production endpoint/device verification pending

## User outcome

用户可看到少量真实 VPN locations、在断开状态选择线路，并自动获得运营方发布的安全更新。远端或网络失败时，已验证可用的线路不会消失。

## Source and transport

- Release requires a build-controlled public HTTPS `ASTER_NODE_SUBSCRIPTION_URL`.
- The App rejects userinfo, password, fragment, placeholder interpolation, localhost, private/link-local/documentation/reserved hosts.
- Fetch uses an ephemeral URLSession with no cookies/cache, bounded request/resource timeout, HTTP 200 and a streaming hard stop at 1 MiB (including chunked/unknown-length responses).
- Redirects are allowed only to the same host over HTTPS.
- The URL is extractable from the binary. It must be a revocable app-specific bootstrap/control endpoint, never a user's personal/master provider subscription secret.

## Catalog installation

- Parse according to SPEC-0059 and cap at 200 safe nodes.
- An update with zero supported safe nodes fails; malformed entries never partially mutate current state before validation completes.
- Persist the complete verified snapshot atomically to App Group `node_catalog.json` with iOS file protection.
- Fetch/parse/persistence/config-selection failure keeps the previous last-known-good snapshot and displays a recoverable message.
- Refresh after six hours, on foreground when stale, and on user request. A last-update timestamp in the future forces refresh rather than extending trust.

## Selection and migration

- Only an explicit selected `VPNNode` writes its validated schema-v2 config to `tunnel_config.json`; Packet Tunnel never reads the remote catalog.
- A location cannot be changed while VPN is connecting, connected, disconnecting or reasserting.
- After refresh, retain selection by matching the current connection fields, then stable ID, then first safe node.
- If a pre-existing valid config is absent from the feed, retain it as “Current Location” to avoid breaking the owner's already-working setup.
- Schema-v1 current configs remain readable; new feed entries follow schema-v2 admission rules.

## UX and copy

- Home shows the selected location near the primary connection action.
- Locations screen states selection, last update, update progress and recoverable failure without fabricating latency, load, “fastest” or “recommended” claims.
- Empty state says locations are temporarily unavailable and offers retry; no test servers or placeholder regions are shown.
- Switching line is a deliberate action; update and selection messages do not overwrite VPN/access errors.

## Security and privacy

- Never log full feed URL, response body, UUID, token or node credentials.
- Stable catalog IDs are opaque SHA-256-derived values.
- TLS authenticates the current feed; response signing/key rotation is not implemented and remains a production hardening option.
- Endpoint ownership, revocation, token rotation, availability monitoring and incident response belong to backend/operations.

## Verification

- Unit coverage: parsing, safe/insecure entries, deduplication, cache restore, stale/future timestamps, last-known-good preservation, selected config preservation and selection writes.
- Build coverage: App/Extension/test bundles compile/link with strict concurrency and generated project.
- Production acceptance: three controlled nodes, add/remove/rename/rotation, corrupted/empty/oversized response, offline cache, Wi-Fi/cellular switching, DNS/exit verification and background refresh on two signed devices.
