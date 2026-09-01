# AGENTS — Aster VPN

## 产品硬约束

- **Core Job：**一键连接 VPN，保障公共或不可信网络下的隐私与安全访问。
- **优先闭环：**开关 → 连接 → 状态反馈 → 订阅理由。
- **不做：**流媒体解锁、广告拦截、杀毒、复杂分流、企业多租户、家庭共享。

## 开工前必读

1. `docs/00_agentic/PRODUCT_BRIEF.md` — 产品范围 SSOT。
2. `PROJECT_STATUS.md` — 当前真实状态、阻塞和风险。
3. `docs/TODO.md` — 依赖有序的下一步工作。
4. 与任务直接相关的 `docs/00_agentic/specs/SPEC-*.md`。
5. `docs/00_agentic/AGENTIC_CODING_GUIDE.md` — 执行、验证与交接协议。

## 证据与状态

- 当前代码、配置、测试和运行证据优先于旧文档。
- 明确区分 `planned`、`implemented`、`build-verified`、`device-verified`、`release-verified`。
- Simulator 构建不能证明 VPN 可用；Network Extension、路由、DNS、网络切换和后台恢复必须真机验证。
- 未获得证据时记录为 Open Question，不自行把建议升级为决定。

## 工程约束

- SwiftUI + MVVM；主 App 负责 UI/编排，Packet Tunnel Extension 负责数据面。
- App 与 Extension 仅通过明确契约通信；当前契约是 App Group 中的 `tunnel_config.json`。
- Extension 保持轻量；不得记录用户流量内容、完整节点凭据或其他敏感数据。
- 修改 `project.yml` 后重新运行 `./setup.sh`，并检查生成工程差异。
- 不静默吞错；用户可恢复的失败必须进入 UI 状态，诊断信息不得泄露凭据。

## 完成定义

- 需求和非目标明确，代码只覆盖本次切片。
- 至少通过相关编译/测试；涉及 VPN 的功能附真机验证记录。
- 更新 `PROJECT_STATUS.md`、`docs/TODO.md` 和受影响的架构/决策文档。
- 交接中列出变更、验证命令、未验证项、风险和下一步。
