# TODO

> Last reviewed: 2026-09-01  
> 只列未完成工作；当前 App Store 目标为 StoreKit-only，不包含第三方广告；Locations catalog、schema v2、三 Tab/圆形连接开关、Account 法律入口和 entitlement 修复见 `PROJECT_STATUS.md`。

## Critical Release Decisions

- [x] **解决 Apple VPN 规则与 AdMob 的冲突**
  - **Decision:** App Store Release target 移除 GMA/UMP/AdMob，免费用户通过 StoreKit paywall 进入订阅；旧 AdMobSSV 后端暂保留，待 Product/Legal 确认后归档。
  - **Remaining evidence:** 重新生成工程、完成 Release archive privacy report 和 ASC answers 对齐。

## High Priority

- [ ] **提供安全的生产 Locations endpoint**
  - **Current:** HTTPS fetch、VLESS/VMess/AnyTLS parser、原子 primary + validated backup catalog、6 小时/前台刷新和 Locations UI 已 build-verified；Release 尚无 `ASTER_NODE_SUBSCRIPTION_URL`。2026-09-01 的真机线路消失已定位为 replacement install 后未重新执行一次性 Debug bootstrap，而不是过滤器删除线路；本次包已重新导入经验证的 catalog/config。Clash Meta AnyTLS password is handled in the dedicated credential field。
  - **Constraint:** URL 会出现在 Info.plist，不能使用个人或 master provider subscription token。
  - **Outcome:** revocable、app-specific 的公开 bootstrap/control endpoint；服务端负责撤销、轮换和最小暴露。
  - **Done when:** 至少 3 个受控节点可刷新/选择；错误更新不覆盖缓存；token 轮换、节点删除、schema v1→v2 和重放场景通过。
  - **Specs:** SPEC-0058、SPEC-0059、SPEC-0062。

- [ ] **完成签名真机连接与线路切换矩阵**
  - **Current:** 真机点击日志已确认失败不是地区化线路字段丢失：先由 `startOrReloadService(nil options)` 引发 Go panic，再由旧 archive 缺少 uTLS 拒绝真实 fingerprint 配置。现已加入 preflight/非空 options，并以 pinned commit 重建 `with_utls,ios,with_low_memory` Libbox；App 与完整 arm64 test bundle build、48 MB package nested codesign 均通过。修复包尚未安装，因为 Thomson’s iPhone 当前虽被识别但 CoreDevice tunnel unavailable。前一版的 49 条线路 bootstrap 已验证，修复后的连接、广告回调、余额扣减和网络出口未验证。
  - **Dependency:** 在 Thomson’s iPhone 完成测试广告与 VPN 系统权限交互；多线路测试还需要安全的生产前 endpoint。
  - **Done when:** 先在用户原设备/线路回归公共 fd resolver；再用两台支持版本 iPhone 覆盖 Wi-Fi/蜂窝、连接/断开、DNS/出口变化、三条线路、后台/前台、网络切换、缓存回退、余额耗尽、Pro 不扣时；日志不含凭据。
  - **Specs:** SPEC-0001、SPEC-0054、SPEC-0056、SPEC-0060、SPEC-0062。

- [ ] **在健康 CI/Simulator 执行完整 XCTest**
  - **Current:** 最新 App、50 unit target 与 9 UI target 均严格 compile/link exit 0；已有 45 unit 执行为 44 pass、1 个明确的 x86_64 Libbox/Go signal-stack skip，0 failure/0 unexpected；新增状态记录/地区标签/缓存迁移/恢复用例尚未 runtime 执行。UI 首轮发现 disclosure contrast 与状态注入问题并已修复，suite 已扩展 Locations、Account、圆形连接开关与最大 Dynamic Type；修复后 CoreSimulator UI query、screenshot、shutdown 及全新 iOS 18.5 设备 migration 同时异常，尚无当前 UI pass evidence。
  - **Command:** `ASTER_TEST_DESTINATION_ID=<arm64-simulator-udid> ./scripts/run_quality_gate.sh`，门禁会保存 `.xcresult`/summary/log 并拒绝任何 skip。
  - **Done when:** 当前 UI 在健康 arm64 simulator/CI 执行通过、0 failures、0 unexpected skips；保存 `.xcresult`；UI 覆盖 Home、Locations、Account、Paywall、圆形连接开关、最大 Dynamic Type、VoiceOver/Reduce Motion 基线和未完成文案扫描。

- [ ] **完成 StoreKit 产品与 sandbox 生命周期**
  - **Current:** 动态价格/试用资格、购买、恢复和 verified entitlement 已实现。
  - **Dependency:** App Store Connect monthly/yearly products、subscription group、价格/intro offer 和法律 URL。
  - **Done when:** sandbox 覆盖 eligible/ineligible trial、购买、pending、cancel、restore、expiry、refund；Pro 无广告且不扣时；文案与 App Store 配置一致。

- [ ] **验证 StoreKit 原生试用与 MRR 策略**
  - **Decision (2026-09-01):** 保留已配置且由 StoreKit 判定用户有资格的 introductory offer；无资格用户直接看到正常订阅 CTA。暂不增加每日签到、可累计免费时长或自定义试用余额：这些权益会稀释 Pro 的无限保护价值、增加滥用与状态复杂度，并可能与 App Store 试用资格产生冲突。
  - **Done when:** 在 Sandbox 覆盖有资格/无资格、购买、取消、恢复和过期路径，确认价格、试用文案和续订条款均由 StoreKit/ASC 返回并按地区显示；上线后按 cohort 比较试用转化、首付率、续订率和退款率。

- [ ] **完成本地化多语言翻译与适配**
  - **Scope:** 以英文为基线，覆盖 `zh-Hans`、`zh-Hant`、`ja`、`es`、`de`、`fr`；Home、Locations、Account、Paywall、系统授权前后提示、错误与恢复购买文案必须自然、用户向、无技术内部术语。
  - **Done when:** 所有用户可见字符串进入 `Localizable.strings`/String Catalog；法律 URL、价格、日期和订阅条款按地区核对；最小屏、最大 Dynamic Type、VoiceOver、文本膨胀和截图逐语言验收。
  - **Owner:** iOS/Product/Localization

- [ ] **归档旧 AdMob SSV（仅在确认无内部实验依赖后）**
  - **Current:** verifier 本地 12/12、audit 0、container smoke 通过。
  - **Dependency:** Product/Legal 确认 StoreKit-only 后端边界与保留期限。
  - **Done when:** 确认无内部实验依赖，删除或归档服务、撤销未使用凭据，并在部署记录中保留最终状态。

## Medium Priority

- [ ] **验证连接优先的转化与留存实验**
  - **P0 首次成功连接：**首次打开直接落 Home，自动准备可用线路；连接失败时提供明确的 `Try again`/`Choose a location`，不要先展示 paywall。
  - **P0 价值后置 paywall：**用户完成一次成功连接或主动点击升级后再展示 Pro 价值；文案聚焦“无限保护时长、更多地区、持续保护”，不使用倒计时、假折扣或阻断式 upsell。
  - **P1 可信状态反馈：**显示 `Connecting → Protected` 的阶段变化、最近一次连接地区和可恢复错误；不展示未经真实数据支持的速度、延迟或“最快”承诺。
  - **P1 温和留存：**仅在用户主动断开、连接失败或连续多次成功连接后提供下一步建议（重连、切换地区、升级）；不使用推送骚扰或 VPN 连接中的插屏。
  - **P1 可度量漏斗：**记录匿名的首次启动、首次点击 Connect、系统授权结果、连接 ready、paywall 查看、购买/恢复结果和 D1/D7 回访；不记录浏览内容、完整节点凭据或流量内容。
  - **MRR 决策（2026-09-01）：**当前版本不增加每日签到或可累计免费时长。它会稀释 Pro 的无限价值、制造刷取与试用资格冲突，并增加免费余额状态机；先使用 StoreKit 原生试用/优惠与“首次成功连接后展示 Pro 价值”的路径。只有当 cohort 数据证明激活率是主要瓶颈时，才测试一次性、封顶的体验时长，并与 StoreKit trial eligibility 明确互斥。
  - **Done when:** 先建立 1 周基线，再一次只改一个变量；以首次 ready 连接率、首次连接耗时、paywall→购买率、D1/D7 留存和退款率共同评估，不只看点击率。

- [ ] **补真实 traffic-ready 证据**
  - **Current:** Provider readiness 只证明 Libbox 启动与 Apple network settings 应用，不证明远端握手、DNS 或 HTTPS 出口。
  - **Done when:** 非敏感 DNS/HTTPS/exit health contract 可区分“系统 connected”和“可用保护”；失败不扣时，UI 可恢复。

- [ ] **完成隐私、凭据和 Archive privacy report**
  - **Current:** Keychain/App Group/File Protection 边界已实现；Privacy Policy/Terms 仅通过 Account/Settings 和 Paywall 法律区域访问。当前 App-owned manifest 与 StoreKit-only 二进制需在最终 Archive 中复核。
  - **Done when:** production dependencies 确定后导出 Archive privacy report；ASC privacy answers、Privacy Policy、保留周期、节点凭据和日志策略逐项一致。

- [ ] **完成连接错误状态机与支持入口**
  - **Outcome:** disconnected/connecting/connected/disconnecting/reasserting/failed/timeout 和位置更新错误都有稳定、可恢复的用户状态。
  - **Done when:** 状态转换/并发操作 unit tests 通过，弱网/失效节点/权限拒绝文案可操作，支持与诊断不暴露凭据。
  - **Specs:** SPEC-0025、SPEC-0028、SPEC-0030、SPEC-0047。

## Release Materials and Supply Chain

  - [ ] **完成 App Store 审核材料** — Privacy/Terms 公网 URL、ASC privacy answers、Review Notes、出口合规、订阅披露、截图、英文 copy review 和 TestFlight smoke；按 `ios-asc-configurator` 的 VPN Privacy UX and User-Facing Copy Gate 复核连接路径、Account/Settings 法律入口和第三方 SDK 文案。
- [ ] **让 Libbox 可复现且可合法分发** — source commit、Go/gomobile、tags 和当前 archive hashes 已记录于 `docs/00_agentic/LIBBOX_PROVENANCE.md`；仍需在干净环境独立复现、归档匹配源、提供 LICENSE/NOTICE/对应源码与 privacy provenance，并取得 GPLv3-or-later 分发法律结论。
- [ ] **归档签名 Release 证据** — Release guard、生产配置、entitlements、embedded provisioning、aggregated privacy manifest、测试 ID/保留 URL 扫描、size/memory/crash 结果全部保存。

## Blocked

- [x] **AdMob App Store 方案** — Resolved by StoreKit-only Release decision; remaining work is archival cleanup only.
- [ ] **生产 Locations 验证** — Blocked by: revocable endpoint 未提供；Unblock when: endpoint 与受控节点可用；Owner: Backend/operations。
- [ ] **签名真机矩阵** — Blocked by: 修复包已签名，但 Thomson’s iPhone 的 CoreDevice tunnel 当前 unavailable；测试广告、VPN 权限、线路连接和网络出口仍需设备端交互，production-like endpoint 也未提供。Unblock when: 解锁并重新建立 USB/device tunnel、安装修复包、完成交互回归并提供受控测试 endpoint；Owner: iOS/operations。
  - Archive gate: `./scripts/validate_signed_archive.sh /absolute/path/to/Aster.xcarchive`；必须在 TestFlight 前通过并保存输出。
- [ ] **StoreKit sandbox** — Blocked by: ASC products 未配置；Unblock when: product IDs/group/offers 可用；Owner: Product/ASC。
- [ ] **最新 UI/arm64 XCTest runtime** — Blocked by: 当前 Mac CoreSimulator UI query/screenshot/shutdown failure，且 x86_64 XCTest 无法安全初始化 bundled Go runtime；Unblock when: healthy arm64 CI/Xcode host 与签名设备；Owner: Build environment。
- [ ] **Libbox release compliance** — Blocked by: build provenance 已记录，但 clean reproducibility、matching-source archive、notices/privacy provenance 和法律结论缺失；Owner: Product/legal。

## Deferred / Won't Do

- **流媒体解锁、广告拦截、杀毒、复杂分流、家庭共享、企业多租户** — Decision: ADR-0001。
- **一次性 60 秒 Demo** — 已被可累计 rewarded time 取代；Decision: ADR-0007。
