# Aster VPN — AI Context

本文件是兼容其他 AI 工具的短入口，不是独立 SSOT。

## Read first

1. `AGENTS.md`
2. `docs/00_agentic/PRODUCT_BRIEF.md`
3. `PROJECT_STATUS.md`
4. `docs/TODO.md`
5. `docs/00_agentic/AGENTIC_CODING_GUIDE.md`
6. 与当前任务相关的 `docs/00_agentic/specs/SPEC-*.md`

## Current truth

- SwiftUI App、Packet Tunnel Extension、App Group 配置和本地 Libbox XCFramework 已存在并通过 unsigned simulator build。
- 当前连接使用 `127.0.0.1:1080` mock 配置；真实节点、真实流量、签名 entitlement 和真机行为未验证。
- StoreKit 2、demo/paywall、Locations、Firebase/Crashlytics、Remote Config 仍是 planned。
- 核心任务只允许“开关 → 连接 → 状态反馈 → 订阅理由”闭环，不扩展到流媒体、广告拦截或企业功能。

完成任何工作时，使用 `planned / implemented / build-verified / device-verified / release-verified` 报告证据，并同步状态与 TODO。

