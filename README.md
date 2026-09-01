# Aster VPN for iOS

Aster VPN 是一个面向美区 iPhone 用户的轻量 VPN。产品只围绕一个核心任务：**一键连接 VPN，在公共或不可信网络下提供隐私与安全访问**。

> 当前阶段：可累计 rewarded access、SSV verifier、多线路订阅 catalog/自动更新、状态记录过滤、地区标签、三 Tab/圆形连接开关、Account 到期状态、StoreKit paywall、首次数据说明与 Apple TUN/Libbox bridge 已实现。当前严格 App/Extension、50-unit 和 9-UI target builds 全部通过；已有 45 unit 实际执行为 44 pass + 1 个明确 x86_64 架构 skip，新增解析/缓存/恢复用例尚未 runtime 执行，UI 修复后运行仍被本机 CoreSimulator query/screenshot/shutdown/clean-device migration 故障阻塞。用户报告旧线路真机连接成功，但该证据早于公共 fd bridge 变更；新增线路切换、生产配置、StoreKit sandbox、Libbox 来源和上线合规仍需证据。更关键的是，AdMob 的数据行为与 Apple VPN Guideline 5.4 存在 release-blocking 冲突。详见 [PROJECT_STATUS.md](PROJECT_STATUS.md)。

## 产品边界

- 做：连接/断开、明确状态、受控 rewarded access、订阅与恢复购买、少量高可用节点、基础帮助与隐私说明。
- 不做：流媒体解锁、广告拦截、杀毒、复杂分流、家庭共享、企业多租户。
- 产品 SSOT：[docs/00_agentic/PRODUCT_BRIEF.md](docs/00_agentic/PRODUCT_BRIEF.md)。

## 当前实现

```text
SwiftUI Home
  -> VPNDataUseDisclosureView (first use)
  -> ConnectionViewModel
  -> NodeCatalogStore
  -> HTTPS subscription -> validated node_catalog.json
  -> Locations -> selected tunnel_config.json
  -> RewardedAdService / UMP -> RewardAccessLedger
  -> SubscriptionStore / StoreKit 2
  -> VPNManager / NETunnelProviderManager
  -> App Group: tunnel_config.json
  -> PacketTunnelProvider
  -> PacketTunnelPlatformInterface / Apple TUN
  -> bundled Libbox.xcframework (sing-box)
```

`TunnelConfiguration` schema v2 支持 VLESS/VMess、TCP/WS/gRPC、TLS/Reality/uTLS 并兼容 schema v1。远端更新采用公开 HTTPS、大小/协议/安全校验、App Group 原子 last-known-good cache；失败不会覆盖已验证线路。仓库不保存生产 feed URL，且不得把个人/master subscription token 放进 Info.plist。

Release 必须注入公开 Privacy URL 与安全的 Locations URL；当前脚本还要求 production AdMob IDs。注意：实现 AdMob 不等于可以发布，Apple VPN Guideline 5.4 与 bundled GMA privacy declarations 的冲突必须先做产品/法律决策，推荐 App Store Release target 使用 StoreKit-only。

生产导向的 AdMob SSV verifier 位于 [Backend/AdMobSSV/README.md](Backend/AdMobSSV/README.md)。它已通过签名、幂等、滚动配额、保留策略测试和容器 smoke，但仍需部署 public HTTPS、配置 AdMob callback 并验证一次 live Google callback。

Release 配置守卫自测：

```bash
scripts/test_release_configuration.sh
```

Release 配置通过 CI/Archive 环境注入，不写入仓库：

```text
ASTER_PRIVACY_POLICY_URL=https://...
ASTER_NODE_SUBSCRIPTION_URL=https://...
ASTER_ADMOB_APP_ID=ca-app-pub-...~...              # 仅在最终保留广告时
ASTER_ADMOB_REWARDED_AD_UNIT_ID=ca-app-pub-.../... # 仅在最终保留广告时
```

`ASTER_NODE_SUBSCRIPTION_URL` 会进入 App bundle，可被提取；它必须可撤销、可轮换且只用于 App bootstrap/control，不得是运营主订阅秘密。

## 快速开始

前置条件：macOS、Xcode、XcodeGen；真机连接还需要 Apple Developer Team、Network Extension 能力和有效 VPN 节点。

```bash
./setup.sh
open Aster.xcodeproj
```

不签名的编译验证：

```bash
xcodebuild -quiet \
  -project Aster.xcodeproj \
  -scheme Aster \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath /tmp/aster-vpn-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

包含 unit/UI test bundles 的严格编译链接验证：

```bash
xcodebuild -quiet \
  -project Aster.xcodeproj \
  -scheme Aster \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/aster-vpn-build-for-testing \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete \
  build-for-testing
```

在健康 arm64 Simulator/CI 上执行完整 59/59 质量门禁并保存 `.xcresult`：

```bash
ASTER_TEST_DESTINATION_ID=<simulator-udid> ./scripts/run_quality_gate.sh
```

门禁同时执行 SSV tests/check/audit、Release 配置自测、plist/entitlement lint、shipping-source 半成品标记扫描，并拒绝任何 XCTest failure 或 skip。可通过 `ASTER_QA_OUTPUT_DIR` 指定证据目录。

签名 Archive 生成后执行提交包校验：

```bash
./scripts/validate_signed_archive.sh /absolute/path/to/Aster.xcarchive
```

该校验拒绝测试 bundle、测试广告 ID、占位/私网 URL、签名或 Packet Tunnel/App Group entitlement 缺失、隐私清单缺失以及错误的 Libbox fd binding。

自动化测试：

```bash
xcodebuild -project Aster.xcodeproj -scheme Aster \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/aster-vpn-derived \
  CODE_SIGNING_ALLOWED=NO test
```

> Simulator 构建只能验证编译与链接；Network Extension 的连接、DNS、路由、后台恢复和网络切换必须在真机验证。
> `build-for-testing` 也不等于用例已运行；只有 `test` 的结果和 `.xcresult` 才能作为 59/59 runtime evidence。

## 文档地图

| 主题 | SSOT |
| --- | --- |
| 产品目标与边界 | [PRODUCT_BRIEF.md](docs/00_agentic/PRODUCT_BRIEF.md) |
| 当前进度、阻塞与风险 | [PROJECT_STATUS.md](PROJECT_STATUS.md) |
| 当前实现架构 | [ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| 技术与产品决策 | [DECISIONS.md](docs/DECISIONS.md) |
| 下一步任务与验收标准 | [TODO.md](docs/TODO.md) |
| 稳定工程知识与 SOP | [KNOWLEDGE.md](docs/KNOWLEDGE.md) |
| AdMob SSV 部署与验证 | [Backend/AdMobSSV/README.md](Backend/AdMobSSV/README.md) |
| Agent 工作协议 | [AGENTIC_CODING_GUIDE.md](docs/00_agentic/AGENTIC_CODING_GUIDE.md) |
| 编号需求规格 | [specs/](docs/00_agentic/specs/) |

## 贡献原则

1. 先读产品 brief、状态、相关 SPEC 和代码证据。
2. 每次只交付一个可验证的纵向切片，优先完成“开关 → 连接 → 状态反馈 → 订阅理由”。
3. 不把 mock、编译通过或模拟器运行写成真机连接完成。
4. 代码、测试和文档同一变更交付；完成定义见 Agentic Coding Guide。
