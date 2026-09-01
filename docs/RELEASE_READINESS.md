# Release Readiness — Aster VPN

> Reviewed: 2026-09-01  
> Decision: **Not ready for App Store submission**

## Evidence Summary

| Area | Current evidence | Release state |
| --- | --- | --- |
| Project generation/entitlements | `./setup.sh` passed; App + Extension generated entitlements contain Packet Tunnel and App Group; self-test passes | Build-verified; signed archive pending |
| App/Extension/resources | Current strict `Aster` target exit 0; latest GMA/UMP, Libbox, AppIcon, PrivacyInfo and embedded PacketTunnel compiled/linked/validated | Current build/link/package-verified |
| iOS automated suite | 59 methods (50 unit, 9 UI); latest `AsterTests` and `AsterUITests` targets each exit 0 | Existing unit `.xcresult`: 44 pass + 1 named x86_64 Libbox skip, 0 failures/unexpected; new parser/region/cache/recovery and Account/tab/control cases await runtime; post-fix UI runtime still CoreSimulator-blocked |
| Reward accounting/anti-abuse | Earned callback, 10-minute reward, 5-minute cooldown, 4 rewards/6 presentations per rolling day, 120-minute cap, Keychain fail-closed, ready-only consumption | Relevant unit tests runtime-passed; live ad/device pending |
| SSV verifier | 12/12 Node tests, syntax check, official registry audit 0, non-root container smoke | Local test-verified; deployment/live callback pending |
| Locations | HTTPS bounded client, VLESS/VMess/AnyTLS parser, status-record filtering, region-only labels, schema v2, last-known-good cache, auto/manual refresh, selection and legacy-current preservation | Build-verified; new parser/region cases and production endpoint/device switching pending |
| StoreKit/paywall | Dynamic products/prices/trial eligibility, purchase, restore, verified entitlement and truthful copy | Build-verified; ASC sandbox pending |
| VPN | Apple TUN/Libbox bridge and readiness contract build; private KVC removed; public Libbox fd binding source/symbol guarded; post-change PacketTunnel compile/link passed | Owner's prior connection predates bridge change; device regression/network matrix missing |
| Copy | English product surfaces contain no TODO/FIXME/mock/placeholder/coming-soon/not-implemented markers; no fake price/latency/recommendation | Static/build-verified; final runtime/localization review pending |
| Privacy | First-use data explanation and lazy ad SDK initialization | Implemented; AdMob/Apple VPN rule conflict unresolved |
| Release config | Test IDs, missing values, unsafe URLs, userinfo, private/reserved hosts rejected | Guard verified; production values absent |
| Repeatable CI gate | `scripts/run_quality_gate.sh` requires an explicit arm64 destination, runs all local safety gates and rejects anything short of 59/59 with 0 skips | Script/fail-fast verified; healthy-host full run pending |
| Signed archive gate | `scripts/validate_signed_archive.sh` rejects test bundles/IDs, unsafe production URLs, invalid signatures/entitlements, missing privacy manifests/Extension and wrong Libbox fd binding | Script/fail-fast verified; signed archive pending |

## Critical Review Findings

### 1. AdMob conflicts with the App Store VPN data rule

Apple Guideline 5.4 states that VPN apps may not use or disclose VPN-app data to third parties for any purpose. The packaged Google Mobile Ads privacy manifest declares linked coarse location, device ID, advertising data and product interaction, including tracking/third-party advertising. Disclosure, UMP and voluntary opt-in do not remove that mismatch.

**Release-safe recommendation:** remove GoogleMobileAds/UserMessagingPlatform and the rewarded placement from the App Store Release target; monetize with StoreKit only. If product retains AdMob, this checklist cannot honestly mark the binary launch-ready without an explicit product/legal risk decision.

**Required mitigation sequence:**

1. Keep rewarded ads user-initiated only, with UMP before GMA initialization, no ad during an active VPN session, earned-callback-only credit, Keychain fail-closed limits, SSV signature verification and duplicate transaction handling. These controls reduce invalid-traffic risk but do not override Apple 5.4.
2. Build the App Store archive from a StoreKit-only target/configuration that does not link GoogleMobileAds/UserMessagingPlatform and does not ship their privacy manifests or rewarded placement. Verify the final Archive privacy report and ASC answers against the actual binary.
3. Keep the ad-enabled build only for internal/device retention experiments until Product/Legal explicitly approves a different App Store path. A runtime kill switch or a consent sheet alone is not sufficient because the SDK and its declared data behavior would still be present in the reviewed binary.

Sources: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [Google Mobile Ads iOS data disclosure](https://developers.google.com/admob/ios/privacy/data-disclosure), [Google rewarded ad policy](https://support.google.com/admob/answer/7313578?hl=en-GB).

### 2. Private Packet Flow access is removed; device regression remains

`PacketTunnelPlatformInterface` no longer reads or dynamically selects any `NEPacketTunnelFlow` implementation detail. It uses only the generated and exported `LibboxGetTunnelFileDescriptor()` binding; Release guards inspect both framework slices and reject the former private-access patterns. The post-change PacketTunnel target compiles and links, but the owner's successful device test predates this change. Re-run it on-device and pin the bundled framework's matching source revision before submission.

### 3. Production location source is absent

Release requires `ASTER_NODE_SUBSCRIPTION_URL`, but no production URL is stored in the repository. This is intentional: a URL in Info.plist can be extracted. Use a revocable app-specific public endpoint, not a personal/master subscription token.

## Copy and UX Audit

- The core hierarchy remains connection-first: status, selected location, primary action, free-time/ad option, then Pro value.
- Reward disclosure states exact reward, frequency and cap before any ad; it never asks for advertiser interaction or frames ad clicking as support.
- Home and Locations do not show fabricated speed, ping, server load, “best” or “fastest” claims.
- StoreKit supplies every displayed price/trial; BEST VALUE is conditional on real annual savings.
- Error copy gives a next action for unavailable location source, update failure, config save, ad privacy/load/show, VPN readiness, purchase and restore.
- Existing current config is labeled “Current Location,” not presented as a fake country.
- First-use screen explains service/data behavior before VPN use, purchase or ad request.
- Production Swift source marker scan has no unfinished user-facing strings. Documentation/task files legitimately contain TODO terms and Debug legitimately contains Google test configuration.
- The first executable UI audit found insufficient deterministic contrast on a translucent disclosure card; cards now use an opaque deep-blue surface. The fix is build-verified and awaits a healthy-host UI audit rerun.

## Required Runtime Matrix

| Scenario | Pass criteria |
| --- | --- |
| Unit/UI automation | 50 unit + 9 UI must execute, 0 failures/unexpected skips other than the documented x86_64 Libbox limitation; `.xcresult` archived |
| First run | Data-use disclosure is complete/reachable on smallest supported screen and largest Dynamic Type; no external ad request before opt-in |
| Locations | Live feed add/remove/rename/rotation; 3 nodes switch; malformed/empty/oversized/offline updates preserve last-known-good |
| Free VPN | Reward adds exactly 10 minutes once; time begins only after ready; zero disconnects; relaunch cannot restore spent time |
| Pro VPN | Verified entitlement hides/disables ad path and never consumes free balance |
| Network | Wi-Fi/cellular, DNS/exit, background/foreground, network switch, reconnect, sleep/wake and disconnect on two supported iPhones |
| StoreKit | Eligible/ineligible trial, purchase, pending, cancel, restore, expiry and refund match UI/entitlement |
| Accessibility | Small screen, largest Dynamic Type, VoiceOver order/labels, Reduce Motion, contrast and reachability |
| Reliability | Repeated connect/switch/disconnect, memory peak under Extension limits, no crash/hang/credential logs |

## Submission Checklist

- [ ] Resolve AdMob/Apple 5.4 product decision.
- [x] Remove private Packet Flow KVC/selector access and guard the public Libbox fd binding.
- [ ] Device-regress the public fd bridge on the owner's previously working route, then complete the network matrix.
- [ ] Supply revocable production locations endpoint and verify three controlled nodes.
- [ ] Execute and archive 59/59 XCTest results on healthy CI; run the x86_64-skipped Libbox check on arm64/device.
- [ ] Complete organization signing, Network Extension approval, App Group and signed Archive/TestFlight checks.
- [ ] Configure and sandbox-test StoreKit products/subscription group/offers.
- [ ] If ads remain: configure production IDs, UMP, public SSV, live callback, test device and monitoring.
- [ ] Publish Privacy/Terms; align ASC privacy answers with aggregated archive manifests.
- [ ] Prepare Review Notes, export-compliance answers, screenshots and final English copy review.
- [ ] Resolve Libbox revision/reproducibility/GPL/notices/privacy provenance.
- [ ] Scan the final Archive for test IDs, placeholder URLs, private selectors, entitlements and embedded privacy manifests.
  - Command: `./scripts/validate_signed_archive.sh /absolute/path/to/Aster.xcarchive`.

`PROJECT_STATUS.md` is the authoritative blocker/evidence ledger. No release claim should be made until every applicable item above has recorded passing evidence.
