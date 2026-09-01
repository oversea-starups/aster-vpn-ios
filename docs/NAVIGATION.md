# Aster VPN File Navigation

## Start Here

| File | Role |
| --- | --- |
| `README.md` | Repository entry, build command, SSOT map |
| `AGENTS.md` | Agent scope and hard constraints |
| `PROJECT_STATUS.md` | Current verified progress, blockers and risks |
| `docs/00_agentic/PRODUCT_BRIEF.md` | Product scope SSOT |
| `docs/TODO.md` | Dependency-ordered remaining work |
| `docs/ARCHITECTURE.md` | Current implemented architecture |
| `docs/DECISIONS.md` | Active decisions and rationale |
| `docs/KNOWLEDGE.md` | Stable engineering knowledge and SOPs |
| `docs/00_agentic/AGENTIC_CODING_GUIDE.md` | Agent execution and verification protocol |

## Source Code

```text
Aster/Sources/
├── Aster/
│   ├── App/AsterApp.swift
│   ├── Core/Configuration/AppConfiguration.swift
│   ├── Core/Services/VPNManager.swift
│   └── Features/
│       ├── Access/
│       ├── Connection/
│       ├── Locations/
│       ├── Onboarding/
│       └── Subscription/
├── PacketTunnel/
│   ├── Info.plist
│   └── PacketTunnelProvider.swift
└── Shared/
    ├── Constants/AppConstants.swift
    └── Models/
        ├── TunnelConfigManager.swift
        ├── TunnelProviderMessage.swift
        └── VPNNode.swift
```

- `Aster`: 主 App UI 和控制面。
- `PacketTunnel`: Network Extension 数据面；保持依赖和资源占用最小。
- `Shared`: 同时编译进 App/Extension 的小型稳定契约，不能依赖主 App 类型。

## Configuration and Generated Artifacts

- `project.yml`: target 与 build setting SSOT。
- `Aster/Config/*.xcconfig`: Debug/Release/Shared 编译配置。
- `Aster/Config/*.entitlements`: 由 `project.yml` properties 生成的 Packet Tunnel + App Group entitlement；Developer Portal/signing 仍需 Archive/真机验证。
- `Aster.xcodeproj`: XcodeGen 生成工程。
- `Aster/Frameworks/Libbox.xcframework`: 预编译 tunnel engine，当前 provenance/version 未固定。
- `scripts/build_core*.sh`: Libbox 构建脚本；当前使用浮动依赖，不适合发布复现。

## Specifications

`docs/00_agentic/specs/` 保存编号需求和历史设计输入。开始功能前只读与任务相关的 SPEC；当 SPEC 与当前代码/Status/ADR 冲突时，记录冲突并按证据优先级处理，不批量把旧建议视为已实现事实。

当前切片重点规格：

- `SPEC-0059-vless-vmess-parsing.md` — subscription parser 与 schema v2 admission rules。
- `SPEC-0060-core-engine-singbox.md` — Libbox/Packet Tunnel integration。
- `SPEC-0061-rewarded-access.md` — rewarded time、频控、SSV、隐私和转化边界。
- `SPEC-0062-node-subscription-catalog.md` — HTTPS catalog、last-known-good 和 Locations selection。
