# Project Status

> Last verified: 2026-09-01  
> Evidence cutoff: current workspace, Xcode 17F42 / iOS SDK 26.5, current strict-concurrency App/Extension/unit/UI target builds, release guards, local Clash Meta conversion evidence for 49 deduplicated nodes, and the owner's report that the pre-bridge-change VPN configuration connected successfully on a real device
> Repository history: Git remote `https://github.com/oversea-starups/aster-vpn-ios.git`; local `main` is synchronized with `origin/main` after a checkpoint and merge commit

## Project Overview

- **Purpose:** 面向美区 iPhone 用户提供可信的一键 VPN，并通过订阅形成主要商业闭环。
- **Implemented slice:** 多线路订阅更新/选择、StoreKit paywall 与到期状态展示、Home/Locations/Account 三 Tab、圆形连接开关、Apple TUN/Libbox bridge、Account/Settings 法律入口和生产配置守卫；App Store 目标为 StoreKit-only，不包含第三方广告。
- **Evidence state:** 当前 App target 已重新生成并严格编译、链接、打包成功，且已移除 GMA/UMP、广告标识和激励入口；最新 `AsterTests` 与 `AsterUITests` targets 也分别 exit 0。AnyTLS 解析、密码凭据和 TLS ALPN builder 测试已通过。Clash Meta 实际配置已转换为 49 个去重节点（VLESS 2、VMess 17、AnyTLS 30），状态记录被过滤，用户标签收敛为地区名，并逐节点完成 catalog 解码、校验与 sing-box JSON 构建。另已使用组织 Team `66B9A952T9`、Network Extension/App Group entitlement 和 Apple Development 身份完成 arm64 Debug device package；主 App、Packet Tunnel 与嵌入 frameworks 的 `codesign --verify --deep --strict` exit 0。由于 CoreDevice 直接写 App Group 根目录存在兼容性错误，已通过仅 Debug 编译的导入桥将经校验的 catalog/config 从 App 沙盒 Library 写入 App Group；暂存文件已在启动后清理，导入流程完成。UI runtime 仍被 CoreSimulator UI query、screenshot、shutdown 及 LaunchServices migration 阻断，不能标记为 UI runtime-passed。用户报告旧线路真机连接成功，但该记录早于 fd bridge 变更，且未提供设备/OS/网络/出口/DNS 记录，因此只记为历史 user-reported device evidence。
- **Release decision:** **Not release-ready.** StoreKit-only 已解决 AdMob 与 Apple VPN 审核规则的产品冲突，但生产节点源、签名、StoreKit sandbox、法律材料、公共 fd bridge 真机回归和完整设备矩阵仍未完成。
- **Current VPN correction (supersedes the earlier installed-package state):** 用户点击连接后的设备日志已把失败定位为两层 Libbox 兼容问题：空 override options 导致 Go panic，以及旧 archive 未启用 uTLS。当前已用 pinned upstream source 重建 `with_utls,ios,with_low_memory` Libbox，加入 config preflight 和非空 options，并适配新 binding；iPhoneOS App build 与完整 arm64 `build-for-testing` 均 exit 0，新 48 MB Debug 包 nested codesign 验证通过。手机现在被识别但 CoreDevice tunnel unavailable，因此修复包尚未安装，不能标记 device-verified。

### 2026-09-01 route disappearance incident

- **Symptom:** 真机更换/重装 Debug 包后，Locations 为空，用户误以为内置线路被删除。
- **Root cause:** 旧 Debug 导入桥是一次性 bootstrap；本次 replacement/fresh-install 路径下 App Group 中已没有 catalog，同时没有重新把已校验的 Clash Meta catalog/config 暂存到 App 沙盒，因此 App 只能看到空的持久化目录。不是地区分组或状态记录过滤逻辑删除了线路。
- **Mitigation:** `node_catalog.json` 现在使用原子写入和 `node_catalog.bak.json` last-known-good 备份；损坏/缺失时保留当前已验证配置并在 UI 显示可恢复提示。每次设备替换/重装都必须重新执行受控导入，生产版本必须由 revocable endpoint 刷新，不得依赖 Debug 内置凭据。
- **Evidence:** `NodeCatalogPersistence` recovery tests compile with the current test target; the current Thomson iPhone package was re-bootstrapped from the validated local catalog/config. VPN handshake and manual line switching remain unverified.

### 2026-09-01 VPN startup incident

- **Observed failure 1:** Extension 在 `startOrReloadService` 内 `SIGABRT`。当前 Libbox 实现会解引用 override options，旧调用传 `nil` 触发 Go nil-pointer panic。
- **Observed failure 2:** 改为非空 options 并加入预检后，`LibboxCheckConfig` 明确返回 `uTLS is not included in this build`；真实线路包含 TLS fingerprint，旧 archive 只有 `ios` tag。
- **Implemented correction:** 启动前 `LibboxCheckConfig`、非空 `LibboxOverrideOptions`、pinned uTLS/low-memory Libbox、更新后的多 DNS iterator 和可选 platform hooks；日志只保留生命周期阶段和脱敏配置。
- **Evidence:** iPhoneOS App build 与 arm64 App/unit/UI `build-for-testing` exit 0；source/toolchain/tags/checksum 见 `docs/00_agentic/LIBBOX_PROVENANCE.md`；48 MB signed Debug package `codesign --verify --deep --strict` exit 0。CoreDevice tunnel 当前不可用，因此安装、连接、DNS/HTTPS/出口和资源占用仍未验证。

## Implemented and Build-Verified

### StoreKit-only monetization

- Home and Account no longer expose rewarded access, free-time balance, ad consent or privacy-choice controls.
- A free user who taps Connect without an active entitlement is taken to the StoreKit paywall; a verified Pro entitlement connects without any timer or ad path.
- The App Store target no longer links GoogleMobileAds/UserMessagingPlatform, carries AdMob identifiers or includes SKAdNetwork entries. `Backend/AdMobSSV` is retained only as a deferred archival candidate until Product/Legal confirms cleanup.
- StoreKit purchase, restore and verified entitlement logic remains in scope; ASC product configuration and sandbox lifecycle are still pending.

### Locations and automatic subscription updates

- `TunnelConfiguration` schema v2 支持 VLESS/VMess/AnyTLS、TCP/WebSocket/gRPC、TLS/uTLS/Reality、TLS ALPN，并兼容读取 schema v1。
- HTTPS subscription client 使用 ephemeral session、连接/资源超时、1 MB 响应上限、HTTP 200、同 host HTTPS redirect、无 cookie/cache。
- Parser 支持明文或 Base64 subscription、最多 200 个 VLESS/VMess/AnyTLS 节点；拒绝重复字段、无效结构、`allowInsecure`、不支持协议/transport、没有 TLS/Reality 的新 VLESS、无 TLS 且 security 为 `none/zero` 的 VMess，以及没有 TLS 或缺少密码的 AnyTLS；“剩余流量/套餐到期/有效期”等状态记录会被识别并丢弃。
- 节点 ID 由规范化连接字段 SHA-256 派生，不暴露 UUID。Catalog 以受保护、原子写入的 App Group `node_catalog.json` 保存 last-known-good；更新失败继续使用已验证缓存。
- 首次启动、进入前台或超过 6 小时时自动刷新；Locations 页支持手动刷新和显式选择。连接期间禁止换线，选择后才将单个验证配置写入 `tunnel_config.json`。
- 现有可连接配置不会因订阅缺失或远端不包含该节点而被删除，会以 “Current Location” 保留，避免升级破坏用户已验证线路。
- Release 构建新增 `ASTER_NODE_SUBSCRIPTION_URL`，必须是公开 HTTPS URL；用户信息、fragment、本地/私网/保留域名和占位变量均被 App 与构建守卫拒绝。

### UI, subscription and review-facing copy

- 根导航固定为 Home、Locations、Account 三个 Tab；Home 与 Account 使用顶部对齐的隐藏滚动指示器容器，避免小屏或大字号下内容被压缩并保留顶部呼吸空间。Home 使用圆形电源开关作为唯一主连接动作；Locations 页顶部为 `VIP` / `Locations` 双 Tab，默认展示真实 StoreKit 套餐列表，第二个 Tab 展示地区选择。
- Home 遵循“状态/圆形开关 → 当前地区 → Pro 主 CTA”的单任务层级；Account 成为唯一的订阅/协议入口。状态记录不会进入可选线路列表。
- Paywall 仅显示 StoreKit 返回的真实产品、价格、trial eligibility 和年度节省；产品不可用时不显示假价格。购买、恢复、verified entitlement 已实现；Account 显示 Aster Pro 的本地化 `Access through <date>` 到期信息，不在缺少 StoreKit 证据时推断续订状态。
- 不在首次启动或首次连接前展示自有隐私说明页/弹窗，避免阻断核心连接路径。Privacy Policy 与 Terms of Use 仅通过 Account/Settings 和 Paywall 法律区域访问。
- 本轮 UI 调整移除了 Locations 页内部的冗余区域标题；用户可通过顶部 Tab 在套餐与地区之间切换。
- Production Swift sources 扫描未发现 TODO/FIXME/mock/placeholder/coming-soon/not-implemented 等面向用户的半成品标记。Debug 配置中的 Google 官方测试 ID 和保留域名不会通过 Release guard。
- 系统 UI contrast audit 已覆盖当前 Home、Locations、Account 与 Paywall 卡片；全局卡片使用确定的不透明 deep-blue surface，target build 已通过，仍需在健康 UI automation host 重跑确认。

### VPN and project configuration

- Packet Tunnel 读取验证后的配置，由 structured builder 生成 sing-box JSON，并通过 Libbox platform interface 应用 Apple IPv4/IPv6/DNS/routes/MTU 与默认接口监听。
- Provider 在启动 core 前调用 `LibboxCheckConfig`，并向 `startOrReloadService` 传入非空 `LibboxOverrideOptions`，把 schema/capability 错误转成可恢复失败而不是 Extension crash。
- Bundled Libbox 固定到 sing-box commit `650ef881c8fb216259e4ebcfbd74234554c39612`，device binary SHA-256 `7aea9ec03b31b0fc45f4533ede934c54b4030b435faeceefc3e139eca2ff677a`，tags 为 `with_utls,ios,with_low_memory`。构建 provenance 已记录，GPL 分发合规仍未关闭。
- Packet Tunnel 不再通过 KVC/selector 读取 `NEPacketTunnelFlow` 私有实现；它只调用 bundled Libbox 头文件公开声明并由 device/simulator binary 导出的 `LibboxGetTunnelFileDescriptor()`。Release guard 同时扫描私有访问模式和公开 symbol，修改后 PacketTunnel target 已独立严格编译链接通过。
- `project.yml` 是 XcodeGen SSOT。App 和 PacketTunnel entitlement 已在 `project.yml` 明确声明 `packet-tunnel-provider` 与 `group.com.astervpn.shared`；`./setup.sh` 后两个生成 plist 均通过自测。
- AppIcon、PrivacyInfo、Info/Extension plist、Google SDK、Libbox、App、Extension、unit/UI test bundles 均在 2026-08-28 基线 `build-for-testing` 中编译链接成功；最终代码又通过当前严格 `Aster`、`AsterTests`、`AsterUITests` target builds。
- `scripts/run_quality_gate.sh` 将 XcodeGen、Release guard、plist/entitlement lint、shipping-source marker scan、SSV check/test/official audit 与 59/59 XCTest 汇总为单一 arm64 CI 门禁；解析 `.xcresult` 后强制 0 failure/0 skip。脚本语法与 missing-destination fail-fast 已验证，本机因 simulator 故障未执行其完整成功路径。

## Verification Evidence

| Check | Result | Evidence level |
| --- | --- | --- |
| `./setup.sh` | Passed; project regenerated after source/config changes | Generated-project verified |
| `scripts/test_release_configuration.sh` | Passed, including entitlements, missing/test IDs, unsafe Privacy/subscription URLs and userinfo rejection | Build-guard verified |
| Generic iOS Simulator Debug build | Previously completed with App, PacketTunnel, Libbox, GMA/UMP and assets | Build-verified |
| Current strict App target build | Exit 0; latest Aster, PacketTunnel, AppIcon/resources, PrivacyInfo and GMA/UMP compiled/linked; embedded Extension validated | Current build/link/package-verified |
| Privacy disclosure UX/copy slice | Pre-use disclosure changed to large-only presentation, user-facing copy, and `Continue`; Home remains focused on connection while legal links stay in Account/Paywall | Simulator App build-verified; current UI runtime remains blocked by CoreSimulator infrastructure |
| Signed arm64 Debug device package | Team `66B9A952T9`; App/PacketTunnel Network Extension + App Group entitlement packaged; nested strict codesign verification exit 0; official Google test ad IDs confirmed | Signed/build/install/launch verified; process remained present on Thomson’s iPhone |
| Clash Meta location conversion | Actual local Clash Meta profile converted to 49 deduplicated VLESS/VMess/AnyTLS nodes; catalog/config decoded and every node built as sing-box JSON | Local conversion/parser/builder verified; validated device bootstrap completed; live tunnel handshake pending |
| Device location state | Generated catalog/config were transferred to the app sandbox, validated by the app, written to App Group, and staging files were removed after launch | Device bootstrap verified without exposing credentials; line selection and network runtime pending |
| Current XCTest target builds | `AsterTests` and `AsterUITests` each exit 0 against the latest App module | Current test-bundle compile/link-verified |
| Reproducible quality gate | `scripts/run_quality_gate.sh`; rejects missing destination, inventory drift, shipping markers, SSV/audit failure and any XCTest skip/failure | Script/self-test verified; healthy arm64 CI run pending |
| Signed archive gate | `scripts/validate_signed_archive.sh`; validates nested signatures, App/Extension entitlements, production IDs/URLs, privacy manifests, test-bundle absence and archived Libbox symbol | Syntax/fail-fast/rejection path verified; production signed archive pending |
| Public Libbox fd bridge | Private KVC/selector source scan is zero; generated device/simulator headers declare and binaries export `LibboxGetTunnelFileDescriptor`; PacketTunnel target strict simulator compile/link exit 0 | Source/symbol/build-verified; device regression pending |
| XCTest inventory | 59 methods: 50 unit + 9 UI | Source/build verified; new parser/region/cache/recovery and Account/tab/connection-control cases not yet runtime-executed |
| Unit execution | iOS 18.5 x86_64: 45 executed, 44 passed, 1 explicit Libbox/Go architecture skip, 0 failures/0 unexpected; test log reports `TEST SUCCEEDED` | Runtime-passed except the named arm64/device compatibility check |
| UI execution | First run executed 4 and exposed disclosure contrast + launch-state issues; both fixed. Current rerun timed out in CoreSimulator UI snapshot/query before product assertions; `simctl screenshot` and Aster-device shutdown also hung | Fix build-verified; **current UI runtime not passed** |
| SSV verifier | 12/12 Node tests, syntax check, audit 0, non-root container smoke | Locally test-verified |
| Real VPN connection | Previous package installed/launched and real click logs captured; those logs exposed nil-options crash followed by missing-uTLS rejection. Corrected package is built and signed but not installed because CoreDevice tunnel is unavailable | Root cause/device diagnostic + build/sign verified; corrected connect, traffic, exit IP and DNS pending |

Earlier iOS 18.x attempts failed before any case started. The later dedicated iOS 26.5 simulator recovered sufficiently to execute and finalize the previous 45-test unit set. UI automation then degraded again: the first actionable run found real UI/test defects, while the post-fix run timed out evaluating its first UI query and even independent simulator screenshot/shutdown commands hung. A separate clean-output App build also stalled in a zero-CPU `actool`; the established incremental output then rebuilt/reprocessed the changed Swift and exited 0. These infrastructure failures are recorded separately from product assertions.

## Release Blockers

1. **StoreKit/ASC production setup.** The App Store binary is StoreKit-only and no longer contains GMA/UMP/AdMob identifiers. App Store Connect products, subscription group, sandbox purchase/pending/cancel/restore/expiry/refund and final privacy answers remain to be verified. See [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
2. **Public fd/uTLS bridge device regression.** Source access to `NEPacketTunnelFlow` private implementation has been removed. Device logs isolated nil options and missing uTLS before `openTun`; both are corrected in a pinned uTLS-enabled build whose headers/symbols and App/test builds pass. The corrected signed package is not yet installed because the paired phone's CoreDevice tunnel is unavailable. Re-run the exact line, then retain connect, DNS/HTTPS/exit, lifecycle and Extension resource evidence.
3. **Secure production location source.** No production `ASTER_NODE_SUBSCRIPTION_URL` is present. A subscription URL embedded in Info.plist is extractable; do not ship a personal/master provider token. Supply a revocable app-specific public bootstrap/control endpoint and test refresh, selection, rollback and token rotation.
4. **Device runtime and release signing.** Organization Team、Network Extension/App Group capability、development profiles、最新 Debug nested signing、installation and launch on the registered Thomson’s iPhone、以及 49 条线路的 App Group bootstrap 均已验证。VPN permission, location switching and tunnel/network runtime remain unverified. Release Archive/TestFlight signing is also still pending.
5. **Device QA.** Record Wi-Fi/cellular, DNS and exit IP, background/foreground, network switch, balance exhaustion, Pro no-charge, line switching, cache fallback and resource peak results on supported real iPhones.
6. **StoreKit production.** App Store Connect monthly/yearly products, subscription group, pricing/trial and sandbox purchase/pending/cancel/restore/expiry/refund remain unverified.
7. **Deferred backend cleanup.** `Backend/AdMobSSV` is no longer part of the App Store target; Product/Legal must confirm whether to archive/delete it and revoke any unused deployment credentials.
8. **Legal, localization and review assets.** Reachable Privacy Policy, ASC privacy answers matching the StoreKit-only binary, Terms review, Review Notes, export-compliance answers, screenshots and final localization are missing.
9. **Libbox license/reproducibility/privacy.** Source revision, Go/gomobile versions, tags and archive checksums are now recorded. Independent clean reproduction, corresponding-source retention, LICENSE/NOTICE/privacy provenance and GPLv3-or-later legal distribution decision are still required.
10. **Runtime automation environment.** Re-run all 7 current UI cases on a healthy simulator/CI host, including post-fix disclosure contrast, Locations and maximum Dynamic Type reachability. Run the x86_64-skipped Libbox configuration compatibility check on arm64 and retain the signed-device tunnel evidence.

## Risks and Open Inputs

| Item | Current risk | Required evidence |
| --- | --- | --- |
| Ad-supported VPN business model | High App Review/privacy rejection risk | Product/legal decision: StoreKit-only release or documented acceptance of risk |
| Production location endpoint | Credential extraction, stale/compromised catalog | Revocable endpoint, ownership, rotation plan, two-device live refresh |
| Provider readiness | Proves local core/settings, not internet exit | DNS/HTTPS/exit probe and signed device matrix |
| Public Libbox fd resolver | A source-clean bridge can still regress actual tunnel startup | Exact previous device scenario + full network matrix; pin matching upstream binary source |
| Production AdMob/SSV | Invalid traffic/reward reconciliation | Console IDs, public SSV, live callback, quota telemetry |
| StoreKit | Incorrect entitlement/conversion copy | ASC sandbox lifecycle matrix |
| Libbox binary | Pinned provenance exists; copyright/reproducibility/privacy obligations remain | Clean hash reproduction, matching-source archive, notices and counsel approval |

## Next Recommended Actions

1. Configure and sandbox-test StoreKit products/subscription group/offers.
2. Provide a revocable production locations endpoint; never place a master subscription secret in the app.
3. Re-run the user's working device scenario with the new public Libbox fd resolver, then record DNS/HTTPS/exit and lifecycle evidence.
4. Re-run the current unit/UI targets on healthy CI (including the arm64 Libbox check), then complete the signed two-device network matrix.
5. Complete the English baseline, translate/adapt all supported locales, then finish ASC, Privacy/Terms, Review Notes, screenshots and Libbox distribution evidence before declaring a release candidate.

## Change Log

| Date | Change | Evidence | Updated by |
| --- | --- | --- | --- |
| 2026-08-28 | Added schema-v2 VLESS/VMess locations catalog, HTTPS auto-refresh, last-known-good cache, Locations UI, first-use data disclosure, lazy ad initialization, XcodeGen entitlement fix and stricter release guards; removed Packet Flow private KVC in favor of the exported Libbox fd binding; expanded suite to 50; created and verified Aster development profiles, built a signed arm64 Debug package, and installed/launched it on Thomson’s iPhone | Setup/release guards and current strict App/unit/UI target builds passed; 43 unit executed with 42 pass + 1 named x86_64 skip; signed nested codesign verification passed with test AdMob IDs; device process remained present after launch; UI post-fix runtime and device feature/network scenarios remain pending | Codex |
| 2026-08-30 | Added secure AnyTLS subscription parsing with dedicated password/TLS ALPN fields, generated a local Clash Meta conversion (49 deduplicated nodes), validated every generated tunnel config, executed the expanded unit suite, and prepared a freshly signed arm64 device package | 45 unit executed with 44 pass + 1 named x86_64 skip; signed nested codesign verification passed; CoreDevice currently reports the paired device unavailable, so installation/App Group copy remains pending | Codex |
| 2026-08-31 | Re-signed the arm64 Debug package with complete application identifiers, installed/launched it on Thomson’s iPhone, and bootstrapped the validated Clash Meta catalog/config through the app sandbox into the App Group | Device installation, launch and process survival verified; staged catalog/config were consumed and removed by the app; VPN handshake, line switching, rewarded callback and network exit remain pending | Codex |
| 2026-08-31 | Added status-record filtering and region-only labels for subscription locations; rebuilt and strictly codesigned the arm64 Debug package | App/PacketTunnel incremental build and nested codesign verification passed; device was temporarily unavailable before the replacement package could be installed; parser/region cases are compile-verified and awaiting runtime execution | Codex |
| 2026-08-31 | Reworked the production UI hierarchy around one circular Home connection control, a single Pro-first access surface, fixed Home/Account layouts, three-tab navigation, Account expiration state and the first-use disclosure sheet | Latest App and arm64 device builds succeeded; nested codesign passed; redesigned package installed/launched on Thomson’s iPhone; simulator XCTest runtime remains blocked by CoreSimulator Mach -308 | Codex |
| 2026-09-01 | Reduced rewarded-ad cooldown from 15 to 5 minutes and changed the per-ad grant to 10 minutes; 24-hour quotas and 120-minute balance cap remain; renamed the user entry to Add time, moved the time summary above the circular switch, put the ad row at the top of the access card, added an extensible Free/Plus/Pro tier model, tuned semantic accent colors, and removed redundant copy | Release guard and 59-test inventory passed; simulator `build-for-testing` and arm64 device build succeeded; nested codesign verified; replacement package installed/launched and validated catalog/config bootstrap consumed its staging files. Targeted XCTest runtime was attempted but CoreSimulator again ended with Mach -308 before assertions | Codex |
| 2026-09-01 | Diagnosed repeated device connection failure as a Libbox nil-options panic followed by a missing-uTLS binary capability; added config preflight/non-null options, rebuilt a pinned minimal uTLS/low-memory archive, adapted the updated Apple binding and added an arm64 uTLS regression | App device build and complete arm64 build-for-testing succeeded; binary tags/symbols/checksums and nested codesign verified. Corrected package installation is pending because CoreDevice currently reports the paired phone tunnel unavailable | Codex |
| 2026-08-26 | Added rewarded access, Keychain anti-abuse ledger, StoreKit paywall, SSV verifier and Apple TUN/Libbox bridge | Historical 17/17 baseline; SSV 12/12/audit/container; later changes require current runtime regression | Codex |
