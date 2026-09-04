# Project Knowledge

> Last verified: 2026-09-04
> 稳定知识放这里；进度见 `PROJECT_STATUS.md`，任务见 `TODO.md`，理由见 `DECISIONS.md`。

## Technical Knowledge

### Shared subscription presentation

- **Pattern:** Keep `SubscriptionPlanCard` and `SubscriptionPurchaseButton` as the single presentation/CTA implementation used by both the Paywall sheet and the VIP sub-tab.
- **Rule:** Button copy must remain outcome-led and StoreKit-aware: choose a plan before selection, an eligible introductory-trial label when StoreKit reports eligibility, and `Unlock unlimited protection` otherwise.
- **Evidence:** `Aster/Sources/Aster/Features/Subscription/Views/SubscriptionPlanComponents.swift`; `PaywallView.swift`; `LocationsView.swift`.

### App 与 Extension 的配置契约

- **Problem:** 两个进程不能共享普通内存，且 Extension 启动时必须获得配置。
- **Current solution:** 使用 `group.com.astervpn.shared` App Group，并读写 `tunnel_config.json`。
- **Important:** group ID 必须在常量、两个 entitlement、签名 capability 中一致；当前 DTO 为 schema v2，读取兼容 schema v1。
- **Evidence:** `AppConstants.swift`、`TunnelConfigManager.swift`、`Aster/Config/*.entitlements`。

### 节点 Catalog 与当前 Extension 配置必须分离

- **Problem:** 远端线路列表会变化且可能损坏，Packet Tunnel 只需要一个已验证当前配置。
- **Solution:** 主 App 使用 bounded HTTPS client + VLESS/VMess parser 安装原子 last-known-good `node_catalog.json`；用户选择后才写 schema-v2 `tunnel_config.json`。更新失败保留缓存和已有 “Current Location”。
- **Security:** Info.plist URL 可被提取，生产只能使用 revocable app-specific endpoint，不能使用个人/master subscription token。新 VLESS feed 条目必须使用 TLS/Reality。
- **Evidence:** ADR-0013；SPEC-0059、SPEC-0062；Locations services/tests。

### Catalog persistence after device replacement

- `node_catalog.json` is written atomically in the App Group and the previous validated bytes are retained as `node_catalog.bak.json`. A corrupt primary falls back to the backup; an unavailable App Group keeps the current validated tunnel configuration visible instead of silently rendering an empty list.
- The Debug Clash Meta import bridge is intentionally one-shot and consumes staged files on launch. A replacement/fresh-install QA path cannot assume the App Group still contains that catalog, so it must verify the group state and re-stage the validated catalog/config before launch when absent. Production must refresh from a revocable endpoint and must not bundle provider credentials.
- **Evidence:** `NodeCatalogPersistence.swift`, `NodeCatalogStore.swift`, `NodeCatalogStoreTests.swift`; incident recorded in `PROJECT_STATUS.md`.

### VPN 状态不是流量可用性

- **Problem:** `NEVPNStatus.connected` 只说明系统 tunnel session 状态，不能证明握手、DNS 和出口流量正常。
- **Solution:** 把状态证据分层：system session、provider/core ready、traffic probe、user-visible state。当前版本已实现版本化 provider/core readiness 与 5 秒 fail-closed，并在 system connected 后执行匿名 HTTPS 2xx/3xx data-plane probe；只有探针成功才进入 Protected。
- **Reusable scenario:** 所有 connect success 埋点、UI 状态和真机验收。
- **Evidence:** `TunnelProviderMessage.swift`、`VPNManager.swift`、`PacketTunnelProvider.swift`；2026-09-04 真机探针返回 200，用户确认最新包可正常使用；独立 DNS/出口 IP 和多设备流量矩阵仍未完成。

### 全隧道启动的代理端点 DNS 引导

- **Problem:** `includeAllNetworks`/`enforceRoutes` 会在 Packet Tunnel 安装物理端点排除路由前启用独占 NECP 策略；此时 Extension 内对代理 hostname 做 `getaddrinfo` 会被拒绝，表现为系统显示 connected 但 HTTPS 不通。
- **Solution:** 主 App 在调用 `startVPNTunnel` 前解析选中线路的 IPv4/IPv6 地址，将受校验的数值地址写入 App Group `tunnel_config.json`。sing-box 使用数值地址拨号，同时保留原 hostname 作为 TLS/SNI；PacketTunnel 只用数值地址生成代理端点 `/32`/`/128` excluded routes，禁止在全隧道启动阶段再次解析代理 hostname。
- **Verification:** 每次用户发起连接都刷新解析结果；配置校验限制为合法数值 IPv4/IPv6 且最多 32 个地址；App 在系统 connected 后必须完成匿名 HTTPS 2xx/3xx data-plane probe，成功才进入 Protected。解析失败、探针失败和保存失败都进入可恢复错误并断开。
- **Reusable scenario:** 任何启用 full-tunnel 的 Network Extension/代理内核组合，都应先完成“物理链路可达性 → 隧道启动 → 真实数据面探针”的分层验证，不要把系统 connected 当作网页可用性证明。
- **Evidence:** `VPNManager.swift`、`TunnelConfigManager.swift`、`SingBoxConfigurationBuilder.swift`、`PacketTunnelPlatformInterface.swift`、`PacketTunnelProvider.swift`；2026-09-04 真机日志记录 pre-resolved endpoint count=1、IPv4 exclusion=1、HTTPS data-plane probe status=200，随后用户确认最新包可正常使用。

### Libbox 在 Apple 平台需要显式 TUN bridge

- **Problem:** 只启动 `LibboxCommandServer` 或由 Provider 独立应用一套 hard-coded network settings，并不会把 `NEPacketTunnelFlow` 交给 sing-box。
- **Solution:** 把 `LibboxPlatformInterfaceProtocol` 实现传给 command server；由 Libbox TunOptions 驱动 address/routes/DNS/MTU settings，应用完成后返回 packet-flow file descriptor，并用 `NWPathMonitor` 报告默认接口变化。
- **Compatibility:** current sing-box TUN schema 使用 `address` array；`inet4_address` 已移除。用 bundled Libbox `checkConfig` 做 executable compatibility regression。
- **Boundary:** 该 bridge 只把 Apple TUN 与 core 正确接通，仍需真机远端握手、DNS 和出口 proof。
- **Public fd boundary:** bridge 已移除 `socket.fileDescriptor` KVC/动态 selector，只调用 generated public declaration 的 `LibboxGetTunnelFileDescriptor()`；PacketTunnel target 内的公开系统 API utun resolver 提供最终符号，release guard 检查源码、头文件和签名扩展，PacketTunnel compile/link 与真机 `openTun` 已通过。用户先前的真机成功记录已由 2026-09-01 修复包更新，但出口/DNS/多线路回归仍是 release blocker。
- **Evidence:** `PacketTunnelPlatformInterface.swift`、`PacketTunnelProvider.swift`、`SingBoxConfigurationBuilder.swift`、SPEC-0060。

### Simulator 与真机验证边界

- **Problem:** Simulator 能编译链接 Network Extension，但不能替代签名、entitlement 和真实网络行为。
- **Solution:** Simulator 用于快速 build/test；真机用于权限提示、路由、DNS、Wi-Fi/蜂窝切换、前后台和资源测量。
- **Evidence:** SPEC-0056；2026-07-17 unsigned simulator build。

### 当前 Libbox 供应链不可复现

- **Problem:** 仓库含预编译框架，但脚本 clone 默认分支并安装 `@latest` gomobile。
- **Solution:** 在发布前固定 upstream commit、Go/gomobile 版本、构建 tags、license/notices、privacy provenance 和 checksum，提供与 bundled binary 匹配的 source，并完成 GPL/商标法律审查。
- **Evidence:** `scripts/build_core.sh`、`scripts/build_core_fix.sh`、`Libbox.xcframework`；framework 内当前无 LICENSE/NOTICE/source revision。

## Business and Product Knowledge

### 单一核心任务

- **Rule:** 功能必须直接改善连接成功、状态可信、公共网络隐私或订阅理由。
- **Scope:** MVP；排除流媒体解锁、广告拦截、杀毒、复杂分流、家庭/企业功能。
- **Evidence:** `docs/00_agentic/PRODUCT_BRIEF.md`、ADR-0001。

### 订阅必须建立在已证明的连接价值上

- **Rule:** 先 device-verify 真实连接，再投入 demo/paywall/实验。
- **Reason:** 否则转化漏斗优化的是不可用体验，也无法区分产品问题与网络问题。
- **Evidence:** AGENTS 的闭环优先级；当前最大风险为真实流量未验证。

### StoreKit-only 首发与免费体验边界

- **Current rule:** App Store target 不包含广告 SDK、UMP、rewarded balance、广告标识或追踪；免费用户仅获得一次性、封顶 10 分钟的 Protected 使用时长，时长只在 VPN 受保护期间累计并在断开时暂停，Pro 通过 StoreKit 订阅获得持续保护。
- **Trial rule:** 产品价格、展示价格和 introductory-offer eligibility 以 StoreKit/ASC 返回为准；不额外叠加每日签到、可累计免费时长或自定义试用余额。
- **Measurement:** Firebase Analytics 仅记录最小化的启动、连接、paywall、购买/恢复事件，不记录浏览内容、目标 URL、DNS 或数据包载荷。
- **Evidence:** `FreeExperienceStore.swift`；`SubscriptionStore.swift`；`AsterAnalytics.swift`；ASC App Privacy labels published 2026-09-01。

### Rewarded ad 频控必须同时限制奖励和展示尝试

> **Historical / superseded:** 该规则属于已移出 App Store target 的 AdMob 实验；首发采用 StoreKit-only 与一次性十分钟首次连接体验，见 ADR-0018。下方内容仅供旧后端归档参考。

- **Problem:** 只限制成功奖励无法阻止反复打开后提前关闭广告，仍可能制造异常展示流量。
- **Rule:** 5 分钟展示冷却；滚动 24 小时最多 4 奖励和 6 次展示；余额必须能容纳完整奖励。
- **Economics:** 每次 10 分钟、每日最多 4 次即 40 分钟免费时长；120 分钟余额上限限制为两小时连续保护；6 次展示允许最多 2 次未完成尝试，但不允许无限重试。
- **Server boundary:** 客户端 guardrail 不等于反作弊后端；生产用 AdMob SSV `transaction_id` 去重并按匿名 installation ID 对账。
- **Evidence:** `RewardAccessPolicy.swift`；SPEC-0061；Google invalid-traffic 和 SSV 指南。

### VPN App 中第三方广告不是纯变现选择

> **Historical rationale:** 当前 App Store target 已移除 GMA/UMP/AdMob；本节解释移除原因，不代表广告仍在产品中。

- **Problem:** bundled GMA privacy manifest 声明 linked coarse location、device ID、advertising data、interaction 和 tracking，而 Apple Guideline 5.4 对 VPN App 向第三方使用/披露数据施加严格限制。
- **Rule:** 首次说明、UMP、opt-in 和 lazy initialization 是必要透明度/最小化措施，但不能被当作化解 5.4 冲突。App Store Release 推荐移除 GMA/UMP/AdMob 并采用 StoreKit-only；保留必须是显式产品/法律风险决定。
- **Evidence:** `PROJECT_STATUS.md`；ADR-0014 unresolved decision；GMA packaged PrivacyInfo。

### SSV 能证明奖励回调，不能证明全部展示尝试

- **Problem:** Google SSV callback 只在 earned reward 时到达；提前关闭与 technical presentation failure 不会到达 server。
- **Rule:** server 验证 raw signed query、Google key、reward/ad contract 与 timestamp，并用 Google transaction/client attempt 双重幂等；按 HMAC installation ID 限制 4 verified rewards/24h。客户端 Keychain 独立限制 6 presentations/24h。
- **Privacy:** raw identifiers、callback query/URL 和 IP 不落盘/不写日志；SQLite 默认保留 30 天，HMAC key 放 deployment secret manager。
- **Current:** verifier 已实现并通过 12/12 tests、npm audit 0 与 container smoke；public HTTPS deployment/live callback 仍是 release blocker。
- **Evidence:** ADR-0011；`Backend/AdMobSSV/`；SPEC-0061。

### 反作弊本地状态必须稳定且 fail-closed

- **Problem:** UserDefaults 可随卸载清空；SSV installation ID 写入失败后继续展示会产生无法稳定关联的回调。
- **Rule:** 奖励账本与匿名 installation ID 使用 this-device-only Keychain；迁移成功才删除旧快照；任何持久化失败都停止新的广告展示。
- **Boundary:** Keychain 只能加强设备端成本，不能替代 SSV 签名、transaction 幂等和服务端配额。
- **Evidence:** ADR-0010；`RewardAccessLedger.swift`；`InstallationIdentity.swift`。

## Workflows and SOPs

### 修改工程设置

- **Trigger:** target、source、bundle ID、framework、entitlement 或 build setting 改变。
- **Steps:**
  1. 修改 `project.yml` 或对应 `.xcconfig`。
  2. 运行 `./setup.sh` 生成 `Aster.xcodeproj`。
  3. 用 `xcodebuild -list` 检查 targets/schemes。
  4. 运行 unsigned simulator build；涉及 capability 时再做签名真机构建。
- **Verification:** 命令退出成功，生成物存在，关键 build setting 与预期一致。
- **Failure handling:** 不在生成的 pbxproj 中做无法回写到 `project.yml` 的孤立修改。

### VPN 真机验证记录

- **Prerequisites:** 非生产测试节点、签名、Network Extension capability、测试 iPhone。
- **Record:** App build、device/OS、network、node region/protocol（不得含凭据）、connect latency、出口/DNS、disconnect、background/network-switch、资源峰值、日志摘要。
- **Pass bar:** 状态与实际流量一致，失败可恢复，无敏感日志。

## Coding and Design Patterns

### 跨进程 DTO 与领域模型分离

- **Use when:** 主 App 要把节点配置交给 Extension。
- **Pattern:** `VPNNode` 保存产品语义；versioned `TunnelConfiguration` 只承载启动所需字段；转换时验证并脱敏。
- **Current:** schema v2 已拆分 `VPNNode` catalog 和 Extension DTO，支持 VLESS/VMess/transport/TLS/Reality/uTLS；schema v1 可迁移读取，parser/builder tests 已编译链接。

### 显式状态机

- **Use when:** 连接流程涉及异步系统 API、权限、超时与恢复。
- **Pattern:** 事件驱动 reducer/actor 产生唯一状态；UI 只渲染状态并发送 intent。
- **Avoid:** 通过比较本地化字符串决定 connect/disconnect 行为。
- **Current:** `ConnectionPresentationState` 使用 enum 决定行为，不再比较本地化字符串。

## Glossary

| Term | Meaning | Source |
| --- | --- | --- |
| Core Job | 一键连接并保护公共/不可信网络访问 | Product Brief |
| Control plane | 主 App 中的节点、订阅、配置与连接编排 | Architecture |
| Data plane | Packet Tunnel Extension 与 Libbox 的流量处理 | Architecture |
| Device-verified | 在记录过设备/OS/网络的真机上完成验收 | ADR-0006 |
