# SPEC-0009 — A/B 实验计划（MRR）

## 实验 1：Paywall 标题
- A: "Unlock Private, Fast VPN"
- B: "Private VPN in One Tap"
- 指标：paywall_view → purchase_success
- 预期：A 更偏价值，B 更偏易用

## 实验 2：CTA 文案
- A: "Start Free Trial"
- B: "Try 3 Days Free"
- 指标：purchase_start → purchase_success

## 分流
- 50/50
- 首次安装分桶
- 运行期：至少 7 天或 500 次 paywall view
