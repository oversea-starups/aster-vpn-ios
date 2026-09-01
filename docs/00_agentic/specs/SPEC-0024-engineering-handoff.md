# SPEC-0024 — 工程实现清单（无代码）

## 必要模块
- VPN 连接模块（NetworkExtension）
- 节点管理模块（配置/分组/锁定）
- 订阅模块（StoreKit 2）
- 状态管理（连接状态机）
- 埋点模块（Firebase/Amplitude）

## 状态机（建议）
- Disconnected → Connecting → Connected
- Disconnected → Connecting → Failed
- Connected → Disconnecting → Disconnected

## 关键配置
- Demo 模式：首次一次性 60 秒
- Paywall 触发：demo_end, 选择 Pro 节点
- Yearly 默认选中

## 关键页面组件
- Home：状态指示 + 主按钮
- Locations：节点列表 + Pro 标签
- Paywall：方案卡片 + CTA
- Settings：开关与帮助入口

## 外部依赖
- VPN Provider SDK（第三方）
- 自建节点配置文件（3x-ui）

## 验收点
- 连接成功率、失败提示
- Paywall 转化漏斗埋点完整
- 订阅与恢复流程可用
