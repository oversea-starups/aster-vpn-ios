# Architecture and Product Decisions

> 本文件只记录已确认的活跃决策。建议、实验和未决项保留在 SPEC 或 `PROJECT_STATUS.md`。

## Decision Index

| ID | Title | Date | Status | Supersedes |
| --- | --- | --- | --- | --- |
| ADR-0001 | 单产品单核心任务 | 2026-01-14 | Active | None |
| ADR-0002 | iOS App + Packet Tunnel 双 target | 2026-01-14 | Active | None |
| ADR-0003 | sing-box 通过 Libbox XCFramework 集成 | 2026-01-14 | Active | None |
| ADR-0004 | App Group 文件作为当前配置 IPC | 2026-01-14 | Active | None |
| ADR-0005 | XcodeGen project.yml 是工程配置 SSOT | 2026-01-14 | Active | None |
| ADR-0006 | 用证据等级报告完成度 | 2026-07-17 | Active | None |
| ADR-0007 | 激励广告时长取代一次性 Demo | 2026-08-26 | Superseded | Planned 60-second demo |
| ADR-0008 | Release 构建拒绝测试广告与缺失法律配置 | 2026-08-26 | Superseded | None |
| ADR-0009 | 扣时与 Protected 状态要求 Provider readiness | 2026-08-26 | Active | None |
| ADR-0010 | 奖励账本与 SSV 身份采用 Keychain fail-closed | 2026-08-26 | Active | UserDefaults-only reward state |
| ADR-0011 | SSV 使用平台中立 Node verifier 与 HMAC SQLite audit | 2026-08-26 | Active | External verifier only as a plan |
| ADR-0012 | Libbox platform bridge 负责 Apple TUN 生命周期 | 2026-08-26 | Active | Provider independently applying hard-coded settings |
| ADR-0013 | 使用 last-known-good 订阅 Catalog 驱动线路选择 | 2026-08-28 | Active | Single preinstalled tunnel config (首发改为内置目录) |
| ADR-0014 | 首次数据说明与按需初始化第三方广告 SDK | 2026-08-28 | Superseded | Every-launch eager UMP/GMA preparation |
| ADR-0015 | Entitlement 必须声明在 XcodeGen SSOT | 2026-08-28 | Active | Empty generated entitlement files |
| ADR-0016 | Packet Tunnel 只使用公开 Libbox fd resolver | 2026-08-28 | Active | KVC access to Packet Flow implementation details |
| ADR-0018 | StoreKit-only 首发与连接优先体验 | 2026-09-01 | Active | ADR-0007, ADR-0014 |
| ADR-0019 | App Privacy 标签与 Firebase Analytics 对齐 | 2026-09-01 | Active | None |

## ADR-0001: 单产品单核心任务

- **Decision:** Aster 只优化“一键连接 VPN，在公共/不可信网络下保护隐私与安全访问”；优先交付“开关 → 连接 → 状态反馈 → 订阅理由”。
- **Reason:** 控制 MVP 范围，并让产品价值和订阅转化可验证。
- **Impact:** 流媒体解锁、广告拦截、杀毒、复杂分流、企业和家庭功能不进入当前路线。
- **Evidence:** `AGENTS.md`；`docs/00_agentic/PRODUCT_BRIEF.md`。

## ADR-0002: iOS App + Packet Tunnel 双 target

- **Decision:** 主 App 负责 UI/控制面，Packet Tunnel Extension 负责隧道和数据面，共享代码仅放稳定小型契约。
- **Reason:** 符合 NetworkExtension 的进程模型并隔离资源受限的数据面。
- **Impact:** Extension 不依赖 UI/业务框架；跨进程状态必须显式建模。
- **Evidence:** `project.yml`；`Aster/Sources/Aster/`；`Aster/Sources/PacketTunnel/`。

## ADR-0003: sing-box 通过 Libbox XCFramework 集成

- **Decision:** 当前 tunnel engine 为 sing-box 的 Libbox mobile binding，并以本地 XCFramework 链接到 PacketTunnel target。
- **Reason:** 需要 VLESS/VMess 与 tun 能力；当前代码和二进制已经采用该方案。
- **Tradeoff:** Framework 约 198 MB，源 revision、构建参数和供应链不可复现；运行内存也未真机测量。
- **Evidence:** `Aster/Frameworks/Libbox.xcframework`；`PacketTunnelProvider.swift`；`SPEC-0060`。
- **Follow-up:** 固定 upstream revision、Go/gomobile 版本、校验值和可复现构建步骤。

## ADR-0004: App Group 文件作为当前配置 IPC

- **Decision:** 主 App 将 Codable 配置写入 App Group 的 `tunnel_config.json`，Extension 启动时读取。
- **Reason:** 实现简单，且 App/Extension 均可访问。
- **Tradeoff:** 需要 schema version、原子写入、文件保护、错误分类和敏感字段边界。
- **Evidence:** `AppConstants.swift`；`TunnelConfigManager.swift`；两个 entitlement 文件。

## ADR-0005: XcodeGen project.yml 是工程配置 SSOT

- **Decision:** target、bundle ID、source、framework 和 build settings 在 `project.yml` 修改，再生成 Xcode project。
- **Reason:** 让工程配置文本化、可审查并适合 agent 自动化。
- **Impact:** 不应只在 Xcode UI 修改生成工程；每次生成后必须验证 build settings 和 diff。
- **Evidence:** `project.yml`；`setup.sh`。

## ADR-0006: 用证据等级报告完成度

- **Decision:** 所有状态使用 `planned → implemented → build-verified → device-verified → release-verified`，不得跳级。
- **Reason:** VPN 的编译、系统状态、真实流量和发布权限是不同证据；旧状态文档曾把它们混为“完成”。
- **Impact:** 状态与交接必须附验证命令/设备/结果；未验证项明确列出。
- **Evidence:** 2026-07-17 repository audit；`PROJECT_STATUS.md`。

## ADR-0007: 激励广告时长取代一次性 Demo

> **Superseded by ADR-0018 (2026-09-01):** 首发 App Store target 改为 StoreKit-only；本节保留历史经济模型，不再描述当前产品行为。

- **Decision:** 免费访问统一为“用户主动观看 rewarded ad → 获得 10 分钟”，不再叠加一次性 60 秒 Demo。
- **Reason:** 两套免费资格会让连接门槛、倒计时、滥用规则和转化归因互相冲突；单一余额模型更透明、可测且便于控制广告频率。
- **Guardrails:** 5 分钟冷却、滚动 24 小时最多 4 奖励/6 展示、120 分钟余额上限、无自动展示；Pro 完全无广告。
- **Evidence:** 用户 2026-08-26 需求；`SPEC-0061`；`RewardAccessPolicy.swift`。

## ADR-0017: Rewarded ad interval and daily economy

- **Decision:** 相邻展示尝试间隔由 15 分钟调整为 5 分钟；奖励调整为每次 10 分钟，滚动 24 小时最多 4 个成功奖励和 6 次展示尝试，余额上限 120 分钟。
- **Reason:** 15 分钟间隔会把一次完整的 4 奖励流程拉长到至少 45 分钟，用户很难在一次短会话中获得可用时长；5 分钟仍要求用户主动等待、避免广告循环。10 分钟奖励让单次广告带来的权益更克制，会员仍明显优于免费路径。
- **Economics:** 4 × 10 分钟 = 每个滚动 24 小时最多 40 分钟免费使用；120 分钟余额上限仍限制为最多两小时的连续保护，避免长期囤积和重置后集中消耗。6 次展示上限为 4 次成功奖励外最多 2 次提前关闭/失败尝试，防止反复拉起广告制造异常请求。
- **Boundary:** 频控是体验和第一层滥用保护，不是 Apple 审核豁免，也不能替代 AdMob SSV 签名校验、transaction 幂等和服务端对账。

## ADR-0008: Release 构建拒绝测试广告与缺失法律/线路配置

> **Superseded by ADR-0018 (2026-09-01):** Release 不再注入或校验 AdMob/UMP 配置；仅保留公开隐私 URL 与其他生产安全配置校验。

- **Decision:** Debug 使用 Google 官方 rewarded test ID；Release 必须注入生产 App ID、rewarded ad unit ID、公开 HTTPS Privacy URL 和公开 HTTPS Locations URL，否则构建失败；本地/私网、userinfo、fragment、占位变量与 IANA 保留域名同样拒绝。
- **Reason:** Google 要求开发期使用测试广告，但测试 ID、空隐私 URL 或占位配置都不能进入发布包。
- **Impact:** CI/App Store archive 必须提供 `ASTER_PRIVACY_POLICY_URL`、`ASTER_NODE_SUBSCRIPTION_URL`；如果最终保留广告，还必须提供 `ASTER_ADMOB_APP_ID` 与 `ASTER_ADMOB_REWARDED_AD_UNIT_ID`。
- **Evidence:** `Aster/Config/*.xcconfig`；`scripts/validate_release_configuration.sh`。

## ADR-0009: 扣时与 Protected 状态要求 Provider readiness

- **Decision:** 系统 `.connected` 之后必须通过版本化 provider message 获得 `dataPlaneReady=true`，才显示 Protected 并开始免费余额扣时；5 秒内无法确认则提示并断开。
- **Reason:** NetworkExtension 状态只说明系统生命周期，不能证明 Extension 已完成引擎启动和网络设置；直接扣时会让用户为不可用阶段付出余额。
- **Boundary:** readiness 不携带配置、凭据或流量内容，也不等同于远端握手、DNS 或出口流量证明，后者仍须真机 probe。
- **Evidence:** `TunnelProviderMessage.swift`；`VPNManager.swift`；`PacketTunnelProvider.swift`；`TunnelProviderMessageTests.swift`。

## ADR-0010: 奖励账本与 SSV 身份采用 Keychain fail-closed

- **Decision:** 奖励余额、展示记录、消费时间和匿名 SSV installation ID 使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` Keychain；旧 UserDefaults 快照成功迁移后删除。账本或稳定身份不可持久化时不得展示广告。
- **Reason:** UserDefaults 可被卸载重置且无法支撑可信频控；身份写入失败后继续展示会让 SSV 配额无法稳定关联，并可能让用户白看广告。
- **Boundary:** 客户端仍不是权威反作弊后端；生产必须验证 Google SSV ECDSA 签名、`transaction_id` 幂等与服务端配额。Keychain 不存广告内容、流量、IP 或节点凭据。
- **Evidence:** `RewardAccessLedger.swift`；`InstallationIdentity.swift`；`RewardedAdService.swift`；`RewardAccessLedgerTests.swift`。

## ADR-0011: SSV 使用平台中立 Node verifier 与 HMAC SQLite audit

- **Decision:** SSV callback 由独立 Node 服务验证 Google ECDSA-SHA256 签名和 reward/ad contract；Google `transaction_id` 与 client attempt ID 双重幂等，按 HMAC 后的 installation ID 执行滚动 24 小时 4 次 verified reward 配额，SQLite 记录默认保留 30 天。
- **Reason:** SSV 是互联网 HTTP callback，不应与尚未选定的 VPN 节点控制面或云厂商绑定；持久事务与唯一索引比进程内状态更能抵抗重启和并发重复回调。
- **Privacy:** 原始 installation/attempt/transaction ID、callback URL/query 和 IP 不落盘、不写日志；HMAC key 由部署 secret manager 持有。
- **Boundary:** Google 只对 earned reward 发送 SSV；服务端无法观测提前关闭或展示失败，故 6 presentations/24h 仍由客户端 Keychain 执行。当前客户端即时发放后由 SSV 对账；要让服务端成为余额唯一权威需另立 authenticated reconciliation contract。
- **Evidence:** `Backend/AdMobSSV/`；12/12 tests；container smoke；`SPEC-0061`。

## ADR-0012: Libbox platform bridge 负责 Apple TUN 生命周期

- **Decision:** `PacketTunnelProvider` 将 `PacketTunnelPlatformInterface` 传给 Libbox；network settings、routes、DNS、MTU、default-interface monitoring 和 tunnel file descriptor 都由 Libbox TUN options 驱动。Provider 仅在 Libbox service 成功启动后报告 ready。
- **Reason:** Apple Network Extension 的 packet flow 不能靠创建一个独立硬编码 `NEPacketTunnelNetworkSettings` 自动进入 sing-box；Libbox 的 Apple integration contract 明确需要 platform interface/openTun bridge。
- **Impact:** sing-box TUN JSON 使用当前 `address` 字段；settings/apply/fd/monitor 任一步失败都 fail closed。fd 取得方式由 ADR-0016 进一步约束。Provider ready 仍不等于远端握手、DNS 或出口成功。
- **Evidence:** `PacketTunnelPlatformInterface.swift`；`PacketTunnelProvider.swift`；`SingBoxConfigurationBuilder.swift`；`TunnelConfigurationTests.swift`；`SPEC-0060`。

## ADR-0013: 使用 last-known-good 订阅 Catalog 驱动线路选择

- **Decision:** 首发 App 从 bundle 内置的已审核 `node_catalog.json` 初始化 App Group；只有显式选中的验证节点写入 Extension 契约 `tunnel_config.json`。远端公开 HTTPS 更新保留为后续迁移，必须可撤销且不得携带个人/master subscription token。
- **Reason:** 线路运营需要远程更新，但未验证响应不能破坏已能连接的配置。Catalog 与 Extension 的最小当前配置分离，可限制数据面复杂度和故障半径。
- **Guardrails:** ephemeral session、同 host HTTPS redirect、1 MB/200 node 上限、拒绝 insecure 新 VLESS、稳定 opaque ID、6 小时/前台刷新、原子 primary + validated backup、失败保留 last-known-good；现有有效配置作为 “Current Location” 保留。Debug device import 是一次性 QA bridge，replacement/fresh install 不得假设其 catalog 仍存在。
- **Security boundary:** Info.plist URL 可被提取；不得嵌入个人/master subscription secret，生产必须使用 revocable app-specific endpoint。当前没有 feed 签名，TLS 与 build-controlled endpoint 是现阶段完整性边界。
- **Evidence:** `NodeSubscriptionClient.swift`；`NodeSubscriptionParser.swift`；`NodeCatalogStore.swift`；`NodeCatalogPersistence.swift`；`LocationsView.swift`；`SPEC-0062`。

## ADR-0014: 首次数据说明与按需初始化第三方广告 SDK

> **Superseded by ADR-0018 (2026-09-01):** 当前首发不展示自定义隐私说明页或广告同意流程；法律入口保留在 Account/Settings 与 Paywall。Apple VPN 授权仅在用户首次点击连接时由系统展示。

- **Decision:** 首次使用 VPN 服务前显示数据用途说明；Google UMP/GMA 只在用户明确打开 Rewarded Access 后初始化，不在冷启动或首次说明前发送广告 SDK 请求。
- **Reason:** VPN 用户需要在使用/购买前知道流量路由与数据用途；未选择广告的用户不应承受广告 SDK 启动请求和隐私成本。
- **Boundary:** 说明必须准确披露 VPN routing、本地线路/余额、可选 Google 广告数据类别和 Apple purchase。它提高透明度，但不能豁免 Apple Guideline 5.4；AdMob 是否能进入 App Store target 仍是 release-blocking 产品/法律决策。
- **Evidence:** `AsterApp.swift`；`VPNDataUseDisclosureView.swift`；`RewardedAdService.swift`；Google SDK packaged PrivacyInfo；`SPEC-0061`。

## ADR-0015: Entitlement 必须声明在 XcodeGen SSOT

- **Decision:** App 与 PacketTunnel 的 Network Extension 和 App Group entitlement 由 `project.yml` target properties 生成；Release self-test 直接检查两个生成 plist。
- **Reason:** 仅设置 entitlement 文件路径、却不在 XcodeGen 声明 values，会让每次 `./setup.sh` 静默生成空 plist，导致签名包无法使用 App Group/Packet Tunnel。
- **Impact:** entitlement 变更必须先改 `project.yml`、运行 `./setup.sh`，再检查生成文件和 signed archive；不允许只在生成工程/Xcode UI 手工修复。
- **Evidence:** `project.yml`；`Aster/Config/*.entitlements`；`scripts/test_release_configuration.sh`。

## ADR-0016: Packet Tunnel 只使用公开 Libbox fd resolver

- **Decision:** `PacketTunnelPlatformInterface.openTun` 在 Apple network settings 应用成功后，只调用生成头文件公开声明的 `LibboxGetTunnelFileDescriptor()`；该符号由 PacketTunnel target 内基于公开 Darwin utun socket ABI 的 resolver 提供。不得通过 KVC、selector 或 `NEPacketTunnelFlow` 私有属性取得 socket fd。
- **Reason:** App Store Guideline 2.5.1 要求 public API，同时 bundled Libbox 的 device/simulator slices 均声明并导出该 binding。当前 upstream Darwin 实现通过系统 socket API 发现 utun fd，不需要 introspect Packet Flow。
- **Guardrails:** Release validation 扫描 `value(forKeyPath:)`、`socket.fileDescriptor` 和动态 selector，并检查两个 framework slice 的头文件和导出 symbol。resolver 返回负值时 tunnel fail closed。
- **Evidence boundary:** 私有访问源代码已清零，PacketTunnel target 已严格编译链接通过；用户先前的成功连接早于此变更，因此真实 iPhone 上的连接、DNS、出口和 lifecycle 仍须回归。Bundled binary 的精确 upstream revision/可复现构建仍是独立供应链 blocker。
- **Evidence:** `PacketTunnelPlatformInterface.swift`；bundled `Libbox.objc.h`/binary symbols；`scripts/validate_release_configuration.sh`；`scripts/test_release_configuration.sh`；`SPEC-0060`。

## Unresolved Release Decision

### AdMob in an App Store VPN binary

- Apple Guideline 5.4 对 VPN App 向第三方使用/披露数据施加严格限制，而 bundled GMA privacy manifest 声明 third-party advertising/tracking 相关的 coarse location、device ID、advertising data 和 interaction。
- **Recommended resolution:** App Store Release target 移除 GMA/UMP/AdMob，免费层和转化由 StoreKit/产品策略重新定义；保留当前 rewarded implementation 不能被当作已满足审核。
- 若产品选择保留广告，必须把高拒审/合规风险作为显式产品与法律决定，而不是通过文案或 UMP 假设已解决。

## ADR-0018: StoreKit-only 首发与连接优先体验

- **Decision:** App Store 首发版本不集成第三方广告、UMP、rewarded access、广告标识或追踪；免费用户获得一次性、封顶 10 分钟的首次连接体验，Pro 通过 StoreKit 订阅获得持续保护。StoreKit 的产品价格和 introductory-offer eligibility 是唯一试用/价格来源。
- **Reason:** VPN 数据与第三方广告披露存在 Apple Guideline 5.4 风险；连接价值必须先被体验，且自定义免费余额会与 Apple 原生试用和反滥用状态复杂度冲突。
- **Impact:** 连接流程不再依赖广告或自定义隐私弹窗；Privacy Policy/Terms 从 Account/Settings 与 Paywall 访问；Apple VPN 授权仅在首次点击连接时触发。
- **Evidence:** `Aster/Sources/Aster/Core/Services/FreeExperienceStore.swift`；`SubscriptionStore.swift`；`AsterApp.swift`；`PROJECT_STATUS.md`。

## ADR-0019: App Privacy 标签与 Firebase Analytics 对齐

- **Decision:** ASC 仅声明“不与你关联的数据”：Device ID、Product Interaction、Performance Data、Other Diagnostic Data；四项用途均为 Analytics，不用于追踪，不声明广告数据。
- **Reason:** 与当前 `FirebaseCore` + `FirebaseAnalyticsCore` 12.18.0、无 IDFA、无广告 SDK 的实际 App target 保持一致。
- **Impact:** 后续新增 SDK、事件参数或数据用途时，必须同步复核 ASC 标签、Privacy Policy 和最终 Archive privacy report。
- **Evidence:** ASC App Privacy 页面于 2026-09-01 显示已发布；`Aster/Sources/Aster/Core/Services/AsterAnalytics.swift`；`PROJECT_STATUS.md`。
