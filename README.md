# Aster VPN iOS transport

This repository publishes the reproducible iOS transport dependency used by
Aster VPN. Release `1.13.16-aster.2` is built from upstream
[`SagerNet/sing-box`](https://github.com/SagerNet/sing-box) tag `v1.13.16`
without source modifications.

The XCFramework contains only the iOS and iOS Simulator slices needed by the
app. The build enables the gVisor TUN stack, uTLS/Reality support, the Clash API
component required internally by Libbox's `CommandServer`, low-memory mode,
and the VMess, VLESS, and AnyTLS outbounds included by sing-box. The Aster app
does not expose a Clash controller or external control port.

## Reproduce

Requirements: Xcode, Swift, Go 1.26+, and Git.

```sh
scripts/build-libbox.sh
swift package compute-checksum build/Libbox.xcframework.zip
```

Expected checksum:

```text
a2a0ba688e6b234666da6cda52a4bd7e15bd4620b23f4b14271c65a85bf0b77b
```

`App/` contains the corresponding Aster VPN iOS application and Packet Tunnel
source used with this transport. Regenerate the Xcode project from
`App/project.yml`; generated projects, signing material, node addresses,
credentials, API keys, and user data are not published here.

## License

The transport, its Apple binding, and the corresponding iOS client source are
distributed under GPL-3.0-or-later. See `LICENSE` and the upstream
source/dependency notices. No App Store binary should be distributed unless the
published source matches that exact binary and all license obligations have
been reviewed.
