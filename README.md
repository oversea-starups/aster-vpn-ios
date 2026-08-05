# Aster VPN iOS transport

This repository publishes the reproducible iOS transport dependency used by
Aster VPN. Release `1.13.16-aster.1` is built from upstream
[`SagerNet/sing-box`](https://github.com/SagerNet/sing-box) tag `v1.13.16`
without source modifications.

The XCFramework contains only the iOS and iOS Simulator slices needed by the
app. The build enables the gVisor TUN stack, uTLS/Reality support, low-memory
mode, and the VMess, VLESS, and AnyTLS outbounds included by sing-box.

## Reproduce

Requirements: Xcode, Swift, Go 1.26+, and Git.

```sh
scripts/build-libbox.sh
swift package compute-checksum build/Libbox.xcframework.zip
```

Expected checksum:

```text
aafddf839a8b0341b34bbc4a8e57d5f919181901f00146c01fe8558fbea1168c
```

No node addresses, credentials, API keys, or user data are published here.

## License

The transport and its Apple binding are distributed under GPL-3.0-or-later.
See `LICENSE` and the upstream source/dependency notices. Aster's distributable
iOS client source will be mirrored here before its first public binary release.
