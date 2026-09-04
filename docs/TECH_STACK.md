# Aster VPN Tech Stack

> Last verified: 2026-09-04
> “Current”来自代码/配置；“Planned”不代表已集成。

## Current implementation

| Area | Choice | Evidence |
| --- | --- | --- |
| Platform | iOS 16+ | `project.yml`, `Shared.xcconfig` |
| Language/UI | Swift 5 mode, SwiftUI | sources and build settings |
| App pattern | MVVM-like Connection feature | `ConnectionView` / `ConnectionViewModel` |
| System VPN | NetworkExtension / Packet Tunnel Provider | source, Info.plist, targets |
| Tunnel engine | bundled Libbox XCFramework (sing-box binding) + Apple platform interface | public exported fd resolver, fresh arm64 build, signed install, tunnel startup and HTTPS data-plane probe verified; user confirmed normal use; independent DNS/exit/multi-device matrix and binary provenance remain unresolved |
| IPC/config | App Group `tunnel_config.json` schema v2 + last-known-good `node_catalog.json` | config/catalog managers and parser |
| Project generation | XcodeGen | `project.yml`, `setup.sh` |
| Subscription | StoreKit 2 | `SubscriptionStore`, `PaywallView` |
| Analytics | Firebase iOS SDK 12.18.0 (`FirebaseCore` + `FirebaseAnalyticsCore`) | `AsterAnalytics`; no IDFA, advertising or attribution SDK |
| Legacy SSV backend | Node 24 container + built-in HTTP + SQLite (`better-sqlite3`) | `Backend/AdMobSSV/`; deferred archive, not an App Store release dependency |
| Privacy declaration | Apple Privacy Manifest + published ASC App Privacy labels + Account/Settings legal links | ASC labels published 2026-09-01; final Archive privacy report pending |
| Tests | XCTest unit + UI | latest 50-unit and 9-UI targets compile/link with exit 0; previous 45-unit `.xcresult` is 44 pass + 1 named x86_64 Libbox skip, while new parser/region/cache cases and post-fix UI runtime remain pending |

## Planned, Not Integrated

| Area | Candidate | Decision needed before implementation |
| --- | --- | --- |
| Crash reporting | Firebase Crashlytics | privacy review and explicit release decision before integration |
| Response signing | Pinned signing key over node catalog | key rotation/revocation and whether TLS + controlled endpoint is sufficient for first release |
| Lint/CI | SwiftLint + CI provider | version pinning and reproducible command |

## Engineering Rules

- `project.yml` is the project configuration SSOT; regenerate after changes.
- Prefer Swift concurrency for new async code, and isolate UI updates on `@MainActor`.
- Keep PacketTunnel dependency surface minimal and measure resources on device.
- Never log traffic content, complete node URLs, UUID/token/receipt or personal data.
- Separate domain models, cross-process DTOs and generated sing-box configuration.
- New dependencies need a clear core-loop benefit, privacy review, failure policy and pinned version.
- A bundled native framework is not releaseable merely because it links: require matching source revision/toolchain, checksum, license/notices, privacy provenance and legal approval.
