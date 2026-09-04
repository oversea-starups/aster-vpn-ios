# SPEC-0061 — Rewarded Access and Conversion UX

> Confirmed: 2026-08-26  
> Updated: 2026-09-01  
> Supersedes the planned one-time 60-second demo as the free-access mechanism.

## User outcome

免费用户可在明确知情并主动选择后观看 AdMob rewarded ad，完整观看后获得可累计的 VPN 使用时长；Pro 用户获得无广告、无限时长。

## Reward contract

- 每个 Google SDK earned-reward 回调发放 10 分钟。
- 未加载、展示失败、提前关闭或重复回调不得发放。
- 余额最多 120 分钟；不足以容纳完整 10 分钟时不得展示广告。
- 奖励账本使用 this-device-only Keychain 持久化并一次性迁移旧 UserDefaults；存储不可用时不得展示广告或重置配额。
- 只有 VPN 系统状态进入 connected、Packet Tunnel 通过版本化 IPC 返回 provider-local readiness，且 App 的匿名 HTTPS data-plane probe 成功后才开始扣时；断开、连接中、Provider 未 ready、探测失败和 Pro 状态不扣时。
- connected 后最多等待 Provider ready，再执行有限次数的真实 HTTPS data-plane probe；任一阶段无法确认时必须提示并断开，不能显示 Protected 或继续扣时。

## Frequency and abuse controls

- 相邻展示尝试至少间隔 5 分钟。
- 滚动 24 小时最多 4 个成功奖励、最多 6 次展示尝试。
- 设备时间明显回拨时暂停广告资格，并提示开启自动日期与时间。
- 客户端为体验与第一层保护；生产使用匿名安装标识、唯一 attempt ID 和 AdMob SSV 做服务端核验与去重。
- 匿名安装标识必须稳定写入 Keychain 后才能展示；写入失败时 fail closed，避免产生无法关联到同一安装的 SSV 回调。
- 技术性 `didFailToPresent` 回滚展示 attempt；用户已经看到广告后主动关闭则保留展示计数与冷却，以免用反复打开/关闭制造异常请求频率。
- SSV 服务必须对 Google 原始 query 的签名部分做 ECDSA-SHA256 验证，要求 `signature`/`key_id` 位于末尾，并以 Google `transaction_id` 与客户端 attempt ID 双重幂等。
- SSV 按 HMAC 后的匿名 installation ID 执行滚动 24 小时最多 4 次 verified reward；原始 installation/attempt/transaction ID 不落盘、不进入日志，记录默认保留 30 天。
- SSV 只收到已产生奖励的 Google callback，看不到提前关闭或技术性展示失败，因此“6 次展示尝试/24h”不能虚构成服务端配额，继续由设备 Keychain 账本执行。
- 当前本地 earned-reward callback 仍即时记入余额，SSV 用于核验、去重、配额和运营对账；若未来要求服务端成为发时长的唯一权威，必须新增经过认证的 client reconciliation API 和签名余额契约。

## Placement and copy

- 广告永不自动弹出，永不打断 VPN，永不出现在 Paywall。
- Home 先展示保护时长，再展示连接状态和主操作；访问卡顶部提供 “Add time · +10 min”，并以整行 “Upgrade to Pro” 作为主转化 CTA；Account 提供同一条次级 rewarded 入口。
- 激励说明页必须公开奖励、5 分钟间隔、滚动 24 小时上限和自愿性质。
- 不使用鼓励点击广告内容或支持开发者的文案。

## Privacy and initialization

- Google UMP/GMA 不得在冷启动或首次数据用途说明之前初始化。
- 用户必须先看到 VPN routing、本地线路/余额、可选 Google 广告数据类别和 Apple purchase handling 的说明；只有用户主动打开 Rewarded Access 后才更新 UMP 并在允许时启动 GMA。
- Bundled GMA privacy manifest 声明 linked coarse location、device ID、advertising data、product interaction 和 tracking/third-party advertising。Apple App Review Guideline 5.4 对 VPN App 使用或向第三方披露数据施加严格限制。
- 首次说明、UMP 或 opt-in 只能提高透明度，不能消除上述审核冲突。App Store Release 是否移除 GMA/UMP/AdMob 是未决的 release-blocking 产品/法律决定；推荐 StoreKit-only Release target。

## Subscription conversion

- Home 同屏说明 Pro 的真实差异：无广告、无计时限制、持续保护。
- Paywall 只显示 StoreKit 返回的产品、价格和试用资格；产品不可用时不显示假价格。
- 免费试用 CTA 只在 StoreKit 报告该产品存在 free-trial offer 且当前用户符合资格时出现；BEST VALUE 只在年费低于 12 个月月费时出现。
- 必须支持恢复购买、自动续费披露、Terms 和生产 Privacy URL。

## Verification

- 纯逻辑测试覆盖频控、余额上限、重复奖励、消费/停止、时间回拨和 Provider readiness IPC 编解码。
- UI 测试覆盖 Home → 激励说明、Home → Paywall、恢复购买入口和无未完成文案。
- SSV tests 使用真实 P-256 key pair/DER signature 和临时磁盘 SQLite，覆盖 query 篡改、key cache、双重幂等、滚动配额、时间戳、reward contract 与 retention；本地当前为 12/12 通过、npm audit 0。
- 发布前使用 Google test ad 验证完整回调，再用生产 AdMob/SSV、StoreKit sandbox 和真机 VPN 完成 device/release verification。
- 当前完整 iOS suite 为 50 unit + 9 UI，最新两个 test targets 均已严格编译链接通过。已有 45 unit 在 iOS 26.5 x86_64 simulator 执行为 44 pass + 1 个明确 Libbox/Go architecture skip、0 failure/0 unexpected；新增状态记录/地区标签/缓存迁移/恢复用例尚未 runtime 执行。UI 首轮发现的 contrast/state-injection 问题已修复，并补入 Locations、Account、圆形连接开关与最大 Dynamic Type 覆盖，但修复后 CoreSimulator UI query/screenshot/shutdown 及全新设备 migration 超时。只有 59/59 在健康 arm64 simulator/CI 实际执行通过时才能升级为完整 test-verified，编译/链接不能替代运行结果。
