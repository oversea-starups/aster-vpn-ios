# SPEC-0004 — 埋点与实验（Vibe Coding）

## 事件设计（最小可观测）
- app_open
- connect_tap
- connect_success (latency_ms, location)
- connect_fail (error_code, location)
- demo_start
- demo_end (reason)
- paywall_view (source)
- purchase_start (product_id)
- purchase_success (product_id, price, currency)
- restore_success
- session_length

## 转化漏斗
1) app_open → connect_tap
2) connect_tap → connect_success
3) paywall_view → purchase_start → purchase_success

## A/B 实验（初期 2 组即可）
- Paywall Title: "Unlock Private, Fast VPN" vs "Private VPN in One Tap"
- CTA 文案: "Start Free Trial" vs "Try 3 Days Free"

## 分流策略
- 50/50 随机
- 首次安装固定分组（避免切换）

## 数据平台
- Firebase Analytics + Crashlytics（零后端优先）
