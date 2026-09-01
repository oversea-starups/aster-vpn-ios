# Bundled Libbox provenance

> Last rebuilt: 2026-09-01  
> State: build-provenance recorded; GPL distribution/legal review and independent reproducibility are still release blockers.

## Current binary

- Upstream: `https://github.com/SagerNet/sing-box.git`
- Branch used: `testing`
- Source commit: `650ef881c8fb216259e4ebcfbd74234554c39612`
- Commit date: `2026-08-31T19:07:48+08:00`
- Go runtime embedded in the linked device binary: `go1.25.5`
- gomobile module: `github.com/sagernet/gomobile v0.1.12`
- Targets: `ios,iossimulator`; minimum iOS `15.0`
- Product tags: `with_utls`; the Apple build also applies `ios` and `with_low_memory`.
- Deliberately excluded as outside Aster's product scope: Tailscale/SSH, USBIP, OpenVPN/OpenConnect, Clash API, QUIC, WireGuard and naive outbound.
- Device archive SHA-256: `7aea9ec03b31b0fc45f4533ede934c54b4030b435faeceefc3e139eca2ff677a`
- Simulator archive SHA-256: `dd33886edab107eb841a5c18f2724ed1b358ec03ea6c608fda25a1670b205f6f`
- Linked device metadata reports `-tags=with_utls,ios,with_low_memory`; simulator slices additionally report `iossimulator`.

The minimal tag selection is required both for uTLS fingerprint compatibility and to keep optional platform interfaces and Network Extension resource cost out of the shipping slice. The generated interface revision adds optional bridge, shell, neighbor-monitor and notification hooks; Aster explicitly reports those optional features unavailable and does not expose them to users.

## 2026-09-01 compatibility incident

The previously bundled archive only reported the `ios` build tag. A real imported node generated a valid uTLS fingerprint block, but `LibboxCheckConfig` rejected it with `uTLS is not included in this build`. Before that error became visible, passing `nil` to upstream `startOrReloadService` caused a Go nil-pointer panic and Extension `SIGABRT` because the current upstream implementation dereferences override options.

The provider now:

1. validates generated JSON with `LibboxCheckConfig` before service startup;
2. always passes a non-null `LibboxOverrideOptions` instance;
3. uses the uTLS-enabled archive above;
4. keeps lifecycle diagnostics free of node credentials;
5. has an arm64 regression test whose generated configuration includes a `chrome` uTLS fingerprint.

## Remaining release work

The upstream license is GPLv3-or-later. Before distribution, retain the exact matching source and build inputs, reproduce both hashes in a clean environment, include required license/notices and corresponding-source offer, and obtain the product/legal distribution decision. A successful build or device connection does not close these obligations.
