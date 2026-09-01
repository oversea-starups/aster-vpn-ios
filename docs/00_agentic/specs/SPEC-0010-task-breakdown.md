# SPEC-0010 — 任务拆解（Vibe Coding）

## 产品与合规
- 定义隐私政策与条款链接（App Store 合规）
- 明确试用说明与自动续费文案
- 订阅产品配置（月/年）

## 体验与流程
- Home 连接页（状态、按钮、反馈）
- 演示连接（首次 60 秒）
- Paywall（年付试用、月付无试用）
- Locations（最少 3–5 节点）
- Settings / Support

## 数据与可观测
- Firebase Analytics / Crashlytics 接入
- 埋点事件按 SPEC-0008
- A/B 实验框架（远程参数）

## QA / 上线
- 连接成功率、失败提示
- 购买/恢复购买流程
- 断网/弱网测试
- 隐私/条款链接可访问
