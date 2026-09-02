# Project Status

> Last verified: 2026-09-02
> Evidence cutoff: current workspace, Xcode 17F42 / iOS SDK 26.5, current strict-concurrency App/Extension/unit/UI target builds, release guards, local Clash Meta conversion evidence for 49 deduplicated nodes, and device logs from the latest connection regression investigation
> Repository history: Git remote `https://github.com/oversea-starups/aster-vpn-ios.git`; local `main` is synchronized with `origin/main` after a checkpoint and merge commit

## Project Overview

- **Purpose:** 面向美区 iPhone 用户提供可信的一键 VPN，并通过订阅形成主要商业闭环。
- **Implemented slice:** 多线路订阅更新/选择、StoreKit paywall 与到期状态展示、Home/Locations/Account 三 Tab、圆形连接开关、Apple TUN/Libbox bridge、Account/Settings 法律入口和生产配置守卫；App Store 目标为 StoreKit-only，不包含第三方广告。
- **Evidence state:** 当前 App target 已重新生成并严格编译、链接、打包成功，且已移除 GMA/UMP、广告标识和激励入口；最新 `AsterTests` 与 `AsterUITests` targets 也分别 exit 0。AnyTLS 解析、密码凭据和 TLS ALPN builder 测试已通过。Clash Meta 实际配置已转换为 49 个去重节点（VLESS 2、VMess 17、AnyTLS 30），状态记录被过滤，用户标签收敛为地区名，并逐节点完成 catalog 解码、校验与 sing-box JSON 构建。另已使用组织 Team `66B9A952T9`、Network Extension/App Group entitlement 和 Apple Development 身份完成 arm64 Debug device package；主 App、Packet Tunnel 与嵌入 frameworks 的 `codesign --verify --deep --strict` exit 0。由于 CoreDevice 直接写 App Group 根目录存在兼容性错误，已通过仅 Debug 编译的导入桥将经校验的 catalog/config 从 App 沙盒 Library 写入 App Group；暂存文件已在启动后清理，导入流程完成。UI runtime 仍被 CoreSimulator UI query、screenshot、shutdown 及 LaunchServices migration 阻断，不能标记为 UI runtime-passed。用户报告旧线路真机连接成功，但该记录早于 fd bridge 变更，且未提供设备/OS/网络/出口/DNS 记录，因此只记为历史 user-reported device evidence。
- **Release decision:** **Not release-ready.** StoreKit-only 已解决 AdMob 与 Apple VPN 审核规则的产品冲突；双语隐私政策/服务条款已发布，App Store Connect App Privacy 标签已发布并与当前 Firebase Analytics、无广告、无账号实现对齐；公共 fd bridge 的真机启动回归已完成，但生产节点治理、Release 签名、StoreKit sandbox、真实远端流量和完整设备矩阵仍未完成。
- **ASC/ASO snapshot (2026-09-01):** 已通过 ASC 读取并更新 15 个 listing locales（`en-US`、`zh-Hans`、`zh-Hant`、`ja`、`ko`、`de-DE`、`fr-FR`、`es-MX`、`it`、`pt-BR`、`nl-NL`、`pl`、`ru`、`tr`、`vi`）的 Name/Subtitle/Keywords/Promotional Text/Description；当前版本 `1.0` 仍为 `REJECTED`。销售地区 v2 读取显示 `CHN` 已为 `available=false`、`USA` 为 `available=true`，未重复写入其他地区。鉴于产品尚未上线，美国区订阅价格已从月 `$4.99`/年 `$39.99` 调整为月 `$8.99`/年 `$59.99` 并完成 price-point readback；`en-US` 的 3 张 1320×2868 截图已上传并回读为 `COMPLETE`。素材与限制见 `App/AppStore/creative/README.md`，定价建议与多语言扩展方案见 `docs/00_agentic/ASO-2026-09.md`。
- **Firebase privacy consistency note (2026-09-01):** 已接入 Firebase iOS SDK 12.18.0 的 `FirebaseCore` 与 `FirebaseAnalyticsCore`，配置文件随 App 包分发；未接入广告 SDK，也不启用 IDFA 收集。ASC Privacy answers 已按该数据收集事实发布，隐私政策和 Apple VPN Guideline 5.4 需继续保持一致，不能恢复“无第三方分析 SDK”的旧承诺。
- **Current VPN correction (supersedes the earlier installed-package state):** 用户点击连接后的设备日志已把失败定位为三层 Libbox 兼容问题：空 override options 导致 Go panic，旧 archive 未启用 uTLS，以及精简构建移除了 `with_clash_api`，导致 `startOrReloadService` 创建内部 clash-server 失败。当前已用 pinned upstream source 重建 `with_gvisor,with_utls,with_clash_api,ios,with_low_memory` Libbox（Clash API 仅作为内部启动依赖，不对外暴露），加入 config preflight 和非空 options，并将 Provider 启动工作移出 XPC 主线程。历史可用实现还把平台对象同时作为内部 command-server handler 与 platform interface；当前修复已恢复该连接方式，并清理短路径下的 stale `command.sock`。最新 gVisor-enabled 包已在 Thomson’s iPhone 上启动 AnyTLS/VMess 配置，Libbox service 与 iOS `NESMVPNSessionStateRunning` 均已出现；真实远端握手、DNS/HTTPS/出口与持续连接稳定性仍待验证。
- **Current connection UX/reliability correction (2026-09-01):** 连接图标已改为静态状态图标，不再使用无限循环旋转；连接尝试增加 25 秒超时并在失败后回到可重试状态。连接前会幂等修复 App Group 中缺失/中断的 `tunnel_config.json`，首次无选中配置时优先选择内置 AnyTLS 线路（保留 VMess/VLESS 供手动选择），并只复用匹配当前 Packet Tunnel bundle ID 的系统 VPN manager。源码与 arm64 device build 均通过；17:37 的安装/启动记录属于上一轮回归，最新 gVisor-enabled 包的设备启动证据见下方 2026-09-02 条目；VPN 远端握手、DNS/HTTPS/出口仍待完成。
- **Traffic path correction (2026-09-01):** 对比旧版可用的 sing-box 配置，补回 `remote-dns`、53 端口 `hijack-dns`、`prefer_ipv4`、IPv6 TUN 地址、gVisor stack 和默认接口自动探测。设备日志曾报告 iOS 对 MTU 9000 返回 `Invalid argument`，因此当前 builder 使用平台兼容的 MTU 1500；真实出口仍需用户在修复包上重连后验证。
- **Free-access status correction (2026-09-02):** 非 Pro 用户始终保留免费体验状态卡；卡片按“可用倒计时 / 尚未使用 / 已用完”显示真实数字和状态。倒计时只累计 VPN 处于 Protected 的使用时间，断开后暂停；不再因一次性体验耗尽而整块消失，也不伪造广告奖励。
- **StoreKit product loading correction (2026-09-01):** ASC 实际订阅 ID 已核对为 `com.astervpn.Aster.premium.monthly` 与 `com.astervpn.Aster.premium.annual`；AppConfiguration 已从旧的、不存在的 `com.aster.vpn.*` ID 切换，真机 Debug 包已重编译、安装并启动。Paywall 的产品 readback 仍需在真机 Apple ID/Sandbox 中完成一次。
- **StoreKit diagnostics (2026-09-01):** Debug builds now log the requested/returned product IDs and non-sensitive StoreKit error domain/code, so an empty Paywall can be distinguished from an ASC/Sandbox availability issue without exposing credentials or changing release copy.
- **Paywall CTA copy (2026-09-02):** The purchase action now says `Unlock unlimited protection`; Apple billing/renewal disclosure remains below the plans, so the CTA leads with the user outcome without hiding subscription terms.
- **PacketTunnel startup bridge correction (2026-09-02):** Device logs showed that the synchronous Libbox bridge could remain blocked inside the first default-interface callback before releasing its readiness semaphore; iOS then reported `Plugin failed` without reaching tunnel network settings. The monitor now signals readiness before entering the Libbox listener callback, while remaining on a system utility queue. The network-settings completion callback is also awaited from a detached Swift task so the Go callback stack cannot deadlock NetworkExtension. PacketTunnel Debug disables code-coverage/testability output and Libbox debug probes. The replacement arm64 package now reaches `Tunnel file descriptor delivered`, `Libbox service started`, and iOS `status changed to connected`/`NESMVPNSessionStateRunning`; remote traffic and DNS/exit verification remain pending.
- **Libbox gVisor rebuild (2026-09-02):** `scripts/libbox-minimal-tags.patch` now retains the gVisor TUN stack, `scripts/build_core.sh` installs both pinned `gomobile` and `gobind`, and Release guards require the same tags. The reviewed replacement hashes are device `70e673633a3251aaccaa95b8b714afb5af699d95d2a96cc430579b3293e058bf` and simulator `fe1a199e6878cfe3442b1afba338d95a4e0c3dbc9dba5912a13f799a6f3301e2`; both binaries contain the expected gVisor/uTLS/Clash bootstrap/low-memory tag string. Generic iPhoneOS build, release configuration tests, installation and Packet Tunnel startup on Thomson’s iPhone pass; remote traffic, DNS/exit and multi-line evidence remain pending.
- **Connection tap feedback correction (2026-09-02):** A post-install tap produced no `Connect requested` or Packet Tunnel lifecycle event because the Home switch was disabled until StoreKit entitlement readiness completed. The switch now accepts the tap and shows a recoverable access-check message; the ViewModel still refuses to start the tunnel until entitlement state is confirmed.
- **Locations entry correction (2026-09-01):** Locations 页面现在默认显示真实线路列表，而不是 VIP 订阅页；VIP 仍可通过顶部切换进入。该改动已随 17:42 真机包安装并启动。

### 2026-09-01 route disappearance incident

- **Symptom:** 真机更换/重装 Debug 包后，Locations 为空，用户误以为内置线路被删除。
- **Root cause:** 旧 Debug 导入桥是一次性 bootstrap；本次 replacement/fresh-install 路径下 App Group 中已没有 catalog，同时没有重新把已校验的 Clash Meta catalog/config 暂存到 App 沙盒，因此 App 只能看到空的持久化目录。不是地区分组或状态记录过滤逻辑删除了线路。
- **Mitigation:** `node_catalog.json` 现在使用原子写入和 `node_catalog.bak.json` last-known-good 备份；首装时从 App Bundle 的 49 条审核线路初始化 App Group，损坏/缺失时显示可恢复提示。未来远端刷新必须使用可撤销 endpoint，不得依赖个人/master 订阅凭据。
- **Evidence:** `NodeCatalogPersistence` recovery tests compile with the current test target; the current Thomson iPhone package was re-bootstrapped from the validated local catalog/config. VPN handshake and manual line switching remain unverified.

### 2026-09-01 VPN startup incident

- **Observed failure 1:** Extension 在 `startOrReloadService` 内 `SIGABRT`。当前 Libbox 实现会解引用 override options，旧调用传 `nil` 触发 Go nil-pointer panic。
- **Observed failure 2:** 改为非空 options 并加入预检后，`LibboxCheckConfig` 明确返回 `uTLS is not included in this build`；真实线路包含 TLS fingerprint，旧 archive 只有 `ios` tag。
- **Implemented correction:** 启动前 `LibboxCheckConfig`、非空 `LibboxOverrideOptions`、pinned uTLS/low-memory Libbox、更新后的多 DNS iterator 和可选 platform hooks；日志只保留生命周期阶段和脱敏配置。
- **Evidence:** iPhoneOS App build 与 arm64 App/unit/UI `build-for-testing` exit 0；source/toolchain/tags/checksum 见 `docs/00_agentic/LIBBOX_PROVENANCE.md`；48 MB signed Debug package `codesign --verify --deep --strict` exit 0。CoreDevice tunnel 当前不可用，因此安装、连接、DNS/HTTPS/出口和资源占用仍未验证。

## Implemented and Build-Verified

### StoreKit-only monetization

- Home and Account do not expose ads or privacy-choice controls. A new user receives one ten-minute protected-usage allowance; its clock runs only while the VPN is protected and pauses on disconnect. The claim is protected by Keychain and is not a daily balance.
- A free user can complete the one-time experience before being shown the StoreKit paywall; a verified Pro entitlement connects without any timer or ad path.
- The App Store target no longer links GoogleMobileAds/UserMessagingPlatform, carries AdMob identifiers or includes SKAdNetwork entries. `Backend/AdMobSSV` is retained only as a deferred archival candidate until Product/Legal confirms cleanup.
- StoreKit purchase, restore and verified entitlement logic remains in scope. Product metadata is loaded with retry-on-entry/foreground behavior; ASC sandbox lifecycle still needs device evidence.

### Locations and automatic subscription updates

- `TunnelConfiguration` schema v2 支持 VLESS/VMess/AnyTLS、TCP/WebSocket/gRPC、TLS/uTLS/Reality、TLS ALPN，并兼容读取 schema v1。
- HTTPS subscription client 使用 ephemeral session、连接/资源超时、1 MB 响应上限、HTTP 200、同 host HTTPS redirect、无 cookie/cache。
- Parser 支持明文或 Base64 subscription、最多 200 个 VLESS/VMess/AnyTLS 节点；拒绝重复字段、无效结构、`allowInsecure`、不支持协议/transport、没有 TLS/Reality 的新 VLESS、无 TLS 且 security 为 `none/zero` 的 VMess，以及没有 TLS 或缺少密码的 AnyTLS；“剩余流量/套餐到期/有效期”等状态记录会被识别并丢弃。
- 节点 ID 由规范化连接字段 SHA-256 派生，不暴露 UUID。Catalog 以受保护、原子写入的 App Group `node_catalog.json` 保存 last-known-good；更新失败继续使用已验证缓存。
- 首次启动、进入前台或超过 6 小时时自动刷新；Locations 页支持手动刷新和显式选择。连接期间禁止换线，选择后才将单个验证配置写入 `tunnel_config.json`。
- 现有可连接配置不会因订阅缺失或远端不包含该节点而被删除，会以 “Current Location” 保留，避免升级破坏用户已验证线路。
- Release 构建仍支持 `ASTER_NODE_SUBSCRIPTION_URL`，但当前首发决策是先使用安装包内置的已审核 catalog、暂不走接口；未来启用远端更新时必须使用公开 HTTPS URL，用户信息、fragment、本地/私网/保留域名和占位变量均被 App 与构建守卫拒绝。

### UI, subscription and review-facing copy

- 根导航固定为 Home、VIP、Account 三个 Tab；Home 与 Account 使用顶部对齐的隐藏滚动指示器容器，避免小屏或大字号下内容被压缩并保留顶部呼吸空间。Home 使用圆形电源开关作为唯一主连接动作；VIP 页顶部为 `VIP` / `Locations` 双 Tab，底部 VIP Tab 每次进入默认显示套餐，首页地点卡进入默认显示地区选择。
- Home 遵循“状态/圆形开关 → 当前地区 → Pro 主 CTA”的操作层级：连接按钮在最上方，地区选择紧随其后，升级区域放在页面底部；Account 成为唯一的订阅/协议入口。状态记录不会进入可选线路列表。
- VIP 子 Tab 与首页触发的 Paywall 弹窗复用同一套餐卡片、BEST VALUE 标识、选中态和购买 CTA；进入后直接加载并展示 StoreKit 返回的套餐名称、描述和本地化价格，用户选择套餐后可直接发起 Apple 购买。StoreKit 原生试用仅对符合资格的用户显示。
- VPNManager 不再在 App 启动时加载或保存 `NETunnelProviderManager`；首次安装的 VPN 授权只会在用户第一次点击连接时触发，避免启动即弹系统授权。
- Paywall 仅显示 StoreKit 返回的真实产品、价格、trial eligibility 和年度节省；产品不可用时不显示假价格。购买、恢复、verified entitlement 已实现；Account 显示 Aster Pro 的本地化 `Access through <date>` 到期信息，不在缺少 StoreKit 证据时推断续订状态。
- 不在首次启动或首次连接前展示自有隐私说明页/弹窗，避免阻断核心连接路径。Privacy Policy 与 Terms of Use 仅通过 Account/Settings 和 Paywall 法律区域访问。
- 本轮 UI 调整移除了 Locations 页内部的冗余区域标题；用户可通过顶部 Tab 在套餐与地区之间切换，首页地点入口和底部 VIP 入口分别保留各自默认子 Tab。
- Production Swift sources 扫描未发现 TODO/FIXME/mock/placeholder/coming-soon/not-implemented 等面向用户的半成品标记。Debug 配置中的 Google 官方测试 ID 和保留域名不会通过 Release guard。
- 系统 UI contrast audit 已覆盖当前 Home、Locations、Account 与 Paywall 卡片；全局卡片使用确定的不透明 deep-blue surface，target build 已通过，仍需在健康 UI automation host 重跑确认。

### VPN and project configuration

- Packet Tunnel 读取验证后的配置，由 structured builder 生成 sing-box JSON，并通过 Libbox platform interface 应用 Apple IPv4/IPv6/DNS/routes/MTU 与默认接口监听。
- Provider 在启动 core 前调用 `LibboxCheckConfig`，并向 `startOrReloadService` 传入非空 `LibboxOverrideOptions`，把 schema/capability 错误转成可恢复失败而不是 Extension crash。
- Bundled Libbox 固定到 sing-box commit `650ef881c8fb216259e4ebcfbd74234554c39612`，device binary SHA-256 `70e673633a3251aaccaa95b8b714afb5af699d95d2a96cc430579b3293e058bf`，simulator binary SHA-256 `fe1a199e6878cfe3442b1afba338d95a4e0c3dbc9dba5912a13f799a6f3301e2`，tags 为 `with_gvisor,with_utls,with_clash_api,ios,with_low_memory`（simulator 另含 `iossimulator`）。构建 provenance 已记录，GPL 分发合规仍未关闭。
- Packet Tunnel 不再通过 KVC/selector 读取 `NEPacketTunnelFlow` 私有实现；它调用 bundled Libbox 头文件公开声明，并由 PacketTunnel target 内的公开系统 API utun bridge 提供 `LibboxGetTunnelFileDescriptor()`。Release guard 同时扫描私有访问模式、公开声明和签名扩展中的最终 symbol；修改后 PacketTunnel target 已严格编译链接通过。
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
| Public Libbox fd bridge | Private KVC/selector source scan is zero; generated headers declare the bridge, PacketTunnel target provides the public-system-API resolver, and the signed extension executable exports `LibboxGetTunnelFileDescriptor`; device `openTun` reached `Tunnel file descriptor delivered` | Source/symbol/build/device bootstrap verified; traffic and DNS regression pending |
| XCTest inventory | 59 methods: 50 unit + 9 UI | Source/build verified; new parser/region/cache/recovery and Account/tab/connection-control cases not yet runtime-executed |
| Unit execution | iOS 18.5 x86_64: 45 executed, 44 passed, 1 explicit Libbox/Go architecture skip, 0 failures/0 unexpected; test log reports `TEST SUCCEEDED` | Runtime-passed except the named arm64/device compatibility check |
| UI execution | First run executed 4 and exposed disclosure contrast + launch-state issues; both fixed. Current rerun timed out in CoreSimulator UI snapshot/query before product assertions; `simctl screenshot` and Aster-device shutdown also hung | Fix build-verified; **current UI runtime not passed** |
| SSV verifier | 12/12 Node tests, syntax check, audit 0, non-root container smoke | Locally test-verified |
| Real VPN connection | gVisor-enabled package installed on Thomson’s iPhone; device log shows AnyTLS/VMess startup, `Libbox command server started`, `Tunnel file descriptor delivered`, `Libbox service started`, and `status changed to connected` / `NESMVPNSessionStateRunning` with no gVisor capability or Plugin failure | Device bootstrap and iOS connection state verified; remote handshake, exit-IP, DNS leak, sustained traffic and multi-line matrix still pending |

Earlier iOS 18.x attempts failed before any case started. The later dedicated iOS 26.5 simulator recovered sufficiently to execute and finalize the previous 45-test unit set. UI automation then degraded again: the first actionable run found real UI/test defects, while the post-fix run timed out evaluating its first UI query and even independent simulator screenshot/shutdown commands hung. A separate clean-output App build also stalled in a zero-CPU `actool`; the established incremental output then rebuilt/reprocessed the changed Swift and exited 0. These infrastructure failures are recorded separately from product assertions.

## Release Blockers

1. **StoreKit/ASC production setup.** The App Store binary is StoreKit-only and no longer contains GMA/UMP/AdMob identifiers. Online products are configured, but sandbox purchase/pending/cancel/restore/expiry/refund and final privacy answers still need device evidence. See [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
2. **Public fd/uTLS bridge traffic regression.** Source access to `NEPacketTunnelFlow` private implementation has been removed. Device logs isolated nil options, missing uTLS and missing gVisor before `openTun`; all are corrected in a pinned gVisor/uTLS-enabled build whose headers/symbols and App/test builds pass. The corrected signed package is installed and reaches `Libbox service started` plus iOS `NESMVPNSessionStateRunning` on the paired phone. The remaining evidence is remote handshake, DNS/HTTPS/exit, lifecycle and Extension resource behavior.
3. **Location source governance.** 首发使用 App Bundle 内置的 49 条已审核线路，不依赖 `ASTER_NODE_SUBSCRIPTION_URL`。上线前仍需完成线路授权、轮换和撤销流程；未来启用远端更新时使用可撤销、应用专用的公开 HTTPS endpoint，绝不放入个人/master token。
4. **Device runtime and release signing.** Organization Team、Network Extension/App Group capability、development profiles、最新 Debug nested signing、installation and launch on the registered Thomson’s iPhone、以及 49 条线路的 App Group bootstrap 均已验证；最新包的 Packet Tunnel bootstrap 与 iOS connected/Running 状态也已确认。VPN permission、远端握手、location switching、DNS/HTTPS/出口、持续稳定性和完整设备矩阵仍未完成。Release Archive/TestFlight signing is also still pending.
5. **Device QA.** Record Wi-Fi/cellular, DNS and exit IP, background/foreground, network switch, balance exhaustion, Pro no-charge, line switching, cache fallback and resource peak results on supported real iPhones.
6. **StoreKit production.** App Store Connect monthly/yearly products, subscription group, pricing/trial and sandbox purchase/pending/cancel/restore/expiry/refund remain unverified.
7. **Deferred backend cleanup.** `Backend/AdMobSSV` is no longer part of the App Store target; Product/Legal must confirm whether to archive/delete it and revoke any unused deployment credentials.
8. **Legal, localization and review assets.** 双语 Privacy Policy/Terms 已发布且 15 个 ASC listing 已包含法律链接；App Store Connect App Privacy answers 已完成并发布（Firebase Analytics、设备/使用数据、无 tracking/广告），仍需进行法律复核，同时完成 Review Notes、出口合规、截图和最终本地化。
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
| 2026-09-02 | 将免费体验从“首次连接后固定 10 分钟墙钟倒计时”修正为一次性 10 分钟 Protected 使用时长；连接断开时暂停，重新进入 Protected 时继续，累计账本落盘并兼容旧到期记录 | `FreeExperienceStore` 定向单元用例已覆盖暂停/恢复和断开期间不扣时；独立 DerivedData 的 App/unit/UI `build-for-testing` exit 0；Simulator 测试运行仍受当前 CoreSimulator 环境阻塞 | Codex |
| 2026-08-28 | Added schema-v2 VLESS/VMess locations catalog, HTTPS auto-refresh, last-known-good cache, Locations UI, first-use data disclosure, lazy ad initialization, XcodeGen entitlement fix and stricter release guards; removed Packet Flow private KVC in favor of the exported Libbox fd binding; expanded suite to 50; created and verified Aster development profiles, built a signed arm64 Debug package, and installed/launched it on Thomson’s iPhone | Setup/release guards and current strict App/unit/UI target builds passed; 43 unit executed with 42 pass + 1 named x86_64 skip; signed nested codesign verification passed with test AdMob IDs; device process remained present after launch; UI post-fix runtime and device feature/network scenarios remain pending | Codex |
| 2026-08-30 | Added secure AnyTLS subscription parsing with dedicated password/TLS ALPN fields, generated a local Clash Meta conversion (49 deduplicated nodes), validated every generated tunnel config, executed the expanded unit suite, and prepared a freshly signed arm64 device package | 45 unit executed with 44 pass + 1 named x86_64 skip; signed nested codesign verification passed; CoreDevice currently reports the paired device unavailable, so installation/App Group copy remains pending | Codex |
| 2026-08-31 | Re-signed the arm64 Debug package with complete application identifiers, installed/launched it on Thomson’s iPhone, and bootstrapped the validated Clash Meta catalog/config through the app sandbox into the App Group | Device installation, launch and process survival verified; staged catalog/config were consumed and removed by the app; VPN handshake, line switching, rewarded callback and network exit remain pending | Codex |
| 2026-08-31 | Added status-record filtering and region-only labels for subscription locations; rebuilt and strictly codesigned the arm64 Debug package | App/PacketTunnel incremental build and nested codesign verification passed; device was temporarily unavailable before the replacement package could be installed; parser/region cases are compile-verified and awaiting runtime execution | Codex |
| 2026-08-31 | Reworked the production UI hierarchy around one circular Home connection control, a single Pro-first access surface, fixed Home/Account layouts, three-tab navigation, Account expiration state and the first-use disclosure sheet | Latest App and arm64 device builds succeeded; nested codesign passed; redesigned package installed/launched on Thomson’s iPhone; simulator XCTest runtime remains blocked by CoreSimulator Mach -308 | Codex |
| 2026-09-01 | Reduced rewarded-ad cooldown from 15 to 5 minutes and changed the per-ad grant to 10 minutes; 24-hour quotas and 120-minute balance cap remain; renamed the user entry to Add time, moved the time summary above the circular switch, put the ad row at the top of the access card, added an extensible Free/Plus/Pro tier model, tuned semantic accent colors, and removed redundant copy | Release guard and 59-test inventory passed; simulator `build-for-testing` and arm64 device build succeeded; nested codesign verified; replacement package installed/launched and validated catalog/config bootstrap consumed its staging files. Targeted XCTest runtime was attempted but CoreSimulator again ended with Mach -308 before assertions | Codex |
| 2026-09-01 | Diagnosed repeated device connection failure as a Libbox nil-options panic followed by a missing-uTLS binary capability; added config preflight/non-null options, rebuilt a pinned minimal uTLS/low-memory archive, adapted the updated Apple binding and added an arm64 uTLS regression | App device build and complete arm64 build-for-testing succeeded; binary tags/symbols/checksums and nested codesign verified. Corrected package installation is pending because CoreDevice currently reports the paired phone tunnel unavailable | Codex |
| 2026-09-02 | 通过最新真机日志确认旧包在 `openTun` 阶段因 `gVisor is not included in this build` 失败；保留 gVisor TUN tag，补齐可复现脚本的 `gobind` 安装，并将 NetworkExtension 网络设置回调改为 detached async bridge | 新 Libbox device/simulator binary hashes 与 tag 字符串已固定；Release configuration tests、generic iPhoneOS build、安装和嵌入框架签名均通过。新包已在 Thomson’s iPhone 上出现 `Libbox service started` 与 `NESMVPNSessionStateRunning`；真实远端握手、DNS/HTTPS/出口和多线路仍待验证 | Codex |
| 2026-09-02 | 统一首页 Paywall 与 VIP 子 Tab 的套餐卡片、BEST VALUE 标识、选中态和购买 CTA；底部第二个 Tab 更名为 VIP，底部进入默认显示 VIP 套餐，首页地点入口默认显示 Locations | `./setup.sh` 后 Debug `build-for-testing` exit 0；新增 UI 断言已编译，当前 CoreSimulator UI runtime 仍受既有环境故障阻塞 | Codex |
| 2026-09-02 | 将包含 VIP Tab/子 Tab 调整的最新 Debug 包安装并启动到 Thomson’s iPhone | `xcodebuild` arm64 device build exit 0；`devicectl device install app`、`device process launch` 均成功；进程 PID 20712 可在设备进程列表中确认；VPN 真实连接/出口仍待单独回归 | Codex |
| 2026-09-01 | 优化 Home 首页层级为“连接状态 → 当前地区 → Pro 升级理由”，缩小连接控件与间距；Locations 的 VIP Tab 直接展示 StoreKit 本地化套餐和价格并可直接购买；明确保留 StoreKit 原生试用、暂不增加签到或自定义免费时长；首次 VPN 授权延迟到用户点击连接 | Simulator build-for-testing 与 Release guard 通过；使用 Team `66B9A952T9` 的 Apple Development 证书成功签名 arm64 Debug 包；由于 CoreDevice 报告 Thomson’s iPhone（UDID `2C61E83A-B248-561F-BFA1-23FC8C2E9578`）tunnel unavailable，修复包尚未安装；VPN 握手、线路切换与 StoreKit Sandbox 生命周期仍待运行验证 | Codex |
| 2026-09-01 | 集成 Firebase 项目 `aster-vpn-ios`：将 GoogleService-Info.plist 内置到 App，使用 FirebaseCore + FirebaseAnalyticsCore，记录 app_open、连接漏斗、首次体验和订阅事件；补齐 app_open 的 first_open 字段 | `./setup.sh`、Release guard、Firebase 依赖解析、App/PacketTunnel arm64 device build、12 个相关 XCTest 均通过；Analytics 在 Simulator 启动日志中完成初始化；真机安装因 CoreDevice tunnel unavailable 未完成，ASC 隐私标签仍待按真实数据收集复核 | Codex |
| 2026-09-01 | 发布 Aster VPN 双语隐私政策与服务条款，移除过时的“无第三方分析 SDK”、账号和同步内容表述，补充 Firebase Analytics、Apple StoreKit、VPN 网络处理和一次性体验说明 | 法律页面仓库提交 `097281a` 已推送；原始 GitHub 文件已回读为 2026-09-01 版本，GitHub Pages 仍可能有短暂缓存；ASC 15 个 App Info localization 的 Privacy Policy URL 已核对正确 | Codex |
| 2026-09-01 | 在 App Store Connect 发布 App Privacy 标签 | 仅“不与你关联的数据”：设备 ID、产品交互、性能数据、其他诊断数据；四项均“用于分析”，未声明追踪或广告；页面显示“几秒钟前由璐伊 赵发布” | Codex |
| 2026-09-01 | 读取 ASC App/版本/本地化/订阅价格与 v2 销售地区；按当前 StoreKit-only 能力更新并扩展 15 个 listing locales 的 ASO 字段与 Description，确认 `CHN` 已关闭；将美国区首发价设置为 `$8.99/月 + $59.99/年` | 15 个语言字段成功 ASC readback；标准 Apple EULA 审计 `valid=true`、15/15 无缺失；15/15 metadata validator valid；月/年 price point readback 分别为 `$8.99`/`$59.99`；当前版本仍 `REJECTED`，完整多语言 UI、截图和 StoreKit sandbox 仍待验证 | Codex |
| 2026-09-01 | 根据首次免费体验能力，将 15 个 ASC listing 的 Name/Keywords/Promotional Text/Description 统一为“免费试用”表达，并明确一次性 10 分钟连接；移除永久免费暗示，保留 Pro 订阅主路径 | 15/15 listing 均有试用披露、隐私政策 URL 和标准 EULA；metadata validator 15/15 无 error/warning；当前版本仍 `REJECTED`，Firebase Analytics/隐私标签一致性和真机网络回归仍待完成 | Codex |
| 2026-09-01 | 用当前模拟器运行的真实 Home UI 生成 3 张 `en-US` 商店截图与 1 张 1600×900 宣传图；替换 ASC 中原有过时截图 | ASC screenshot set `72744f83-c915-4036-8602-f29608d40774` 回读 3 张均为 `COMPLETE`、1320×2868；模拟器无法证明 Network Extension 可用，提交审核前需用真机正常连接状态重新捕获 | Codex |
| 2026-09-01 | 使用 Xcode 已配置的开发签名重新构建并再次安装 Aster 到已连接的 Thomson’s iPhone | `xcodebuild` 真机 Debug exit 0；主 App、PacketTunnel 与嵌入组件签名校验通过；`devicectl device install app` 与 `device process launch` 均成功；设备网络/VPN 握手尚未验证 | Codex |
| 2026-09-01 | 移除连接图标无限旋转；增加连接超时与失败收敛；连接前修复 App Group 配置；无选中配置时优先内置 AnyTLS 线路；仅复用匹配 Packet Tunnel bundle ID 的 VPN manager | arm64 iPhoneOS build exit 0；`codesign --verify --deep --strict`、`devicectl device install app`、启动和进程存在均成功；VPN runtime evidence 待用户点击回归 | Codex |
| 2026-09-01 | 完成项目归档交接：同步 StoreKit-only、内置线路、Firebase Analytics、ASC 隐私标签和发布阻塞状态；将旧广告/首次隐私页方案标记为 superseded | 文档扫描与一致性复核通过；更新 README、ARCHITECTURE、DECISIONS、KNOWLEDGE、TODO、RELEASE_READINESS、ROADMAP、TECH_STACK | Codex |
| 2026-08-26 | Added rewarded access, Keychain anti-abuse ledger, StoreKit paywall, SSV verifier and Apple TUN/Libbox bridge | Historical 17/17 baseline; SSV 12/12/audit/container; later changes require current runtime regression | Codex |
