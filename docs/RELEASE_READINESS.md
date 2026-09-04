# Release Readiness — Aster VPN

> Reviewed: 2026-09-04
> Decision: **Not ready for App Store submission**

## Evidence Summary

| Area | Current evidence | Release state |
| --- | --- | --- |
| Project generation/entitlements | `./setup.sh` passed; App + Extension generated entitlements contain Packet Tunnel and App Group; self-test passes | Build-verified; signed archive pending |
| App/Extension/resources | Current strict `Aster` target is StoreKit-only and has no GMA/UMP; Libbox, AppIcon, PrivacyInfo and embedded PacketTunnel remain required | Build-verified; release archive required |
| iOS automated suite | 59 methods (50 unit, 9 UI); latest `AsterTests` and `AsterUITests` targets each exit 0 | Existing unit `.xcresult`: 44 pass + 1 named x86_64 Libbox skip, 0 failures/unexpected; new parser/region/cache/recovery and Account/tab/control cases await runtime; post-fix UI runtime still CoreSimulator-blocked |
| Monetization | StoreKit products, purchase, restore and verified entitlement; no third-party ad SDK in the App Store binary | Build-verified; ASC sandbox pending |
| SSV verifier | 12/12 Node tests, syntax check, official registry audit 0, non-root container smoke | Local test-verified; deployment/live callback pending |
| Locations | Bundled 37-node catalog (AnyTLS 32, VLESS Reality 2, VMess 3), optional HTTPS client for future updates, VLESS/VMess/AnyTLS parser, status-record filtering, region-only labels, schema v2, last-known-good cache and selection | Bundle/build-verified; latest tunnel use user-confirmed; live future-feed switching and multi-line matrix pending |
| StoreKit/paywall | Dynamic products/prices/trial eligibility, purchase, restore, verified entitlement and truthful copy | Build-verified; ASC sandbox pending |
| VPN | Apple TUN/Libbox bridge and readiness contract build; private KVC removed; public Libbox fd binding source/symbol guarded; post-change PacketTunnel compile/link, signed install, tunnel startup and HTTPS data-plane probe passed | Latest device package normal use is user-confirmed; independent DNS/exit/network matrix and release archive remain pending |
| Copy | English product surfaces contain no TODO/FIXME/mock/placeholder/coming-soon/not-implemented markers; no fake price/latency/recommendation | Static/build-verified; final runtime/localization review pending |
| Privacy | Account/Settings and Paywall legal links; VPN routing and on-device configuration are described in user-facing language; no ad SDK in the App Store binary; ASC App Privacy labels published | Static/build-verified; final Archive privacy report still pending |
| Release config | Test IDs, missing values, unsafe URLs, userinfo, private/reserved hosts rejected | Guard verified; production values absent |
| Repeatable CI gate | `scripts/run_quality_gate.sh` requires an explicit arm64 destination, runs all local safety gates and rejects anything short of 59/59 with 0 skips | Script/fail-fast verified; healthy-host full run pending |
| Signed archive gate | `scripts/validate_signed_archive.sh` rejects test bundles/IDs, unsafe production URLs, invalid signatures/entitlements, missing privacy manifests/Extension and wrong Libbox fd binding | Script/fail-fast verified; signed archive pending |

## Critical Review Findings

### 1. AdMob conflict is resolved for the App Store target

Apple Guideline 5.4 states that VPN apps may not use or disclose VPN-app data to third parties for any purpose. The current App Store target removes Google Mobile Ads, UMP, rewarded placement, ad identifiers and SKAdNetwork entries, so the prior SDK/data mismatch is no longer shipped.

**Decision:** monetize with StoreKit only. Keep the legacy SSV service outside the app target only until Product/Legal confirms archival.

**Required mitigation sequence:**

1. Build the App Store archive from the StoreKit-only target and verify its final privacy report and ASC answers against the actual binary.
2. Archive the legacy SSV service after confirming no internal experiment depends on it.

Sources: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [Google Mobile Ads iOS data disclosure](https://developers.google.com/admob/ios/privacy/data-disclosure), [Google rewarded ad policy](https://support.google.com/admob/answer/7313578?hl=en-GB).

### 2. Private Packet Flow access is removed; device regression remains

`PacketTunnelPlatformInterface` no longer reads or dynamically selects any `NEPacketTunnelFlow` implementation detail. It calls the generated public declaration of `LibboxGetTunnelFileDescriptor()`; the PacketTunnel target supplies the small public-system-API utun bridge, while the bundled Libbox framework provides the core engine and internal Clash bootstrap only. Release guards reject the former private-access patterns and verify the bridge in the signed extension executable. The post-change PacketTunnel target compiles and links, but the owner's successful device test predates this change. Re-run it on-device and pin the bundled framework's matching source revision before submission.

### 3. Bundled location source is now the release source of truth

The current release includes a reviewed, validated catalog in the app bundle and seeds the App Group on first launch, so a fresh install does not depend on a network endpoint. `ASTER_NODE_SUBSCRIPTION_URL` remains optional for a later revocable, app-specific update service; never embed a personal/master provider token.

## Copy and UX Audit

- The core hierarchy remains connection-first: status, selected location, primary action, then Pro value.
- Home and Locations do not show fabricated speed, ping, server load, “best” or “fastest” claims.
- StoreKit supplies every displayed price/trial; BEST VALUE is conditional on real annual savings.
- Error copy gives a next action for unavailable location source, update failure, config save, VPN readiness, purchase and restore.
- Existing current config is labeled “Current Location,” not presented as a fake country.
- No custom privacy disclosure sheet is shown on launch; Privacy Policy and Terms remain reachable from Account/Settings and Paywall. The system VPN permission is deferred until the user taps Connect.
- Production Swift source marker scan has no unfinished user-facing strings. Documentation retains historical AdMob rationale, but the current App/Release source contains no ad SDK references.
- The first executable UI audit found insufficient deterministic contrast on a translucent disclosure card; cards now use an opaque deep-blue surface. The fix is build-verified and awaits a healthy-host UI audit rerun.

## Required Runtime Matrix

| Scenario | Pass criteria |
| --- | --- |
| Unit/UI automation | 50 unit + 9 UI must execute, 0 failures/unexpected skips other than the documented x86_64 Libbox limitation; `.xcresult` archived |
| First run | Data-use disclosure is complete/reachable on smallest supported screen and largest Dynamic Type; no external ad request before opt-in |
| Locations | Live feed add/remove/rename/rotation; 3 nodes switch; malformed/empty/oversized/offline updates preserve last-known-good |
| Free VPN | One-time allowance totals exactly 10 minutes of Protected usage; time begins only after ready, pauses on disconnect, resumes on reconnect, and relaunch cannot reset consumed time |
| Pro VPN | Verified entitlement hides/disables ad path and never consumes free balance |
| Network | Wi-Fi/cellular, DNS/exit, background/foreground, network switch, reconnect, sleep/wake and disconnect on two supported iPhones |
| StoreKit | Eligible/ineligible trial, purchase, pending, cancel, restore, expiry and refund match UI/entitlement |
| Accessibility | Small screen, largest Dynamic Type, VoiceOver order/labels, Reduce Motion, contrast and reachability |
| Reliability | Repeated connect/switch/disconnect, memory peak under Extension limits, no crash/hang/credential logs |

## Submission Checklist

- [x] Resolve AdMob/Apple 5.4 product decision: App Store binary is StoreKit-only; backend AdMobSSV is retained only as deferred code until separately retired.
- [x] Remove private Packet Flow KVC/selector access and guard the public Libbox fd binding.
- [ ] Device-regress the public fd bridge on the owner's previously working route, then complete the network matrix.
- [x] Bundle the reviewed location catalog and seed it on first launch; endpoint refresh remains a future migration.
- [ ] Execute and archive 59/59 XCTest results on healthy CI; run the x86_64-skipped Libbox check on arm64/device.
- [ ] Complete organization signing, Network Extension approval, App Group and signed Archive/TestFlight checks.
- [ ] Configure and sandbox-test StoreKit products/subscription group/offers.
- [ ] Retire or archive the unused `Backend/AdMobSSV` service after Product/Legal confirms no internal experiment depends on it.
- [x] Publish Privacy/Terms and ASC App Privacy answers; align the final Archive privacy report with the published labels before submission.
- [ ] Prepare Review Notes, export-compliance answers, screenshots and final English copy review.
- [ ] Resolve Libbox revision/reproducibility/GPL/notices/privacy provenance.
- [ ] Scan the final Archive for test IDs, placeholder URLs, private selectors, entitlements and embedded privacy manifests.
  - Command: `./scripts/validate_signed_archive.sh /absolute/path/to/Aster.xcarchive`.

`PROJECT_STATUS.md` is the authoritative blocker/evidence ledger. No release claim should be made until every applicable item above has recorded passing evidence.
