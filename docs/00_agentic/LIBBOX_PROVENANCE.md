# Bundled Libbox provenance

> Last rebuilt: 2026-09-02
> State: build-provenance recorded; GPL distribution/legal review and independent reproducibility are still release blockers.

## Current binary

- Upstream: `https://github.com/SagerNet/sing-box.git`
- Branch used: `testing`
- Source commit: `650ef881c8fb216259e4ebcfbd74234554c39612`
- Commit date: `2026-08-31T19:07:48+08:00`
- Go runtime embedded in the linked device binary: `go1.25.5`
- gomobile module: `github.com/sagernet/gomobile v0.1.12`
- Targets: `ios,iossimulator`; minimum iOS `15.0`
- Product tags: `with_gvisor`, `with_utls` and the internal `with_clash_api` bootstrap module; the Apple build also applies `ios` and `with_low_memory`. The Clash API is not exposed or bound to a user-facing listener. gVisor is required for the configured Network Extension TUN stack.
- Deliberately excluded as outside Aster's product scope: Tailscale/SSH, USBIP, OpenVPN/OpenConnect, QUIC, WireGuard and naive outbound. `with_clash_api` is the sole exception: it is retained only for Libbox's internal bootstrap/reload path and no Clash control listener or user-facing API is exposed.
- Device binary SHA-256: `70e673633a3251aaccaa95b8b714afb5af699d95d2a96cc430579b3293e058bf`
- Simulator binary SHA-256: `fe1a199e6878cfe3442b1afba338d95a4e0c3dbc9dba5912a13f799a6f3301e2`
- Linked device metadata reports `-tags=with_gvisor,with_utls,with_clash_api,ios,with_low_memory`; simulator slices additionally report `iossimulator`.

The minimal tag selection is required for the configured gVisor TUN stack and uTLS fingerprint compatibility while keeping optional platform interfaces and Network Extension resource cost out of the shipping slice. The generated interface revision adds optional bridge, shell, neighbor-monitor and notification hooks; Aster explicitly reports those optional features unavailable and does not expose them to users.

## 2026-09-01 compatibility incident

The previously bundled archive only reported the `ios` build tag. A real imported node generated a valid uTLS fingerprint block, but `LibboxCheckConfig` rejected it with `uTLS is not included in this build`. Before that error became visible, passing `nil` to upstream `startOrReloadService` caused a Go nil-pointer panic and Extension `SIGABRT` because the current upstream implementation dereferences override options.

The provider now:

1. validates generated JSON with `LibboxCheckConfig` before service startup;
2. always passes a non-null `LibboxOverrideOptions` instance;
3. uses the uTLS-enabled archive above;
4. keeps lifecycle diagnostics free of node credentials;
5. has an arm64 regression test whose generated configuration includes a `chrome` uTLS fingerprint.

The first gVisor-enabled replacement was built from the same pinned source and toolchain after device logs showed the previous archive rejected the configured `gvisor` TUN stack. The reproducible build script now installs both `gomobile` and `gobind`, and its hash/tag checks match the binaries above.

## Remaining release work

The upstream license is GPLv3-or-later. Before distribution, retain the exact matching source and build inputs, reproduce both hashes in a clean environment, include required license/notices and corresponding-source offer, and obtain the product/legal distribution decision. A successful build or device connection does not close these obligations.
