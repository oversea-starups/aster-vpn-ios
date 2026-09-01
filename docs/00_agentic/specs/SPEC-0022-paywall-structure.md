# SPEC-0022 — Paywall 结构与组件（可直接编码）

## 布局结构（自上而下）
1. 顶部关闭按钮（2 秒后出现）
2. 标题 + 副标题
3. 价值点列表（3 条）
4. 方案卡片（Yearly 默认选中，Monthly 次之）
5. 主 CTA（Start Free Trial）
6. 次 CTA（Continue Limited）
7. Restore Purchases
8. 法律链接（Terms / Privacy）
9. 试用说明脚注

## 交互细节
- Yearly 卡片默认高亮
- 点击卡片切换选中态
- CTA 文案随选中方案动态变化
- 点击 Continue Limited 关闭 paywall

## 视觉要点
- Yearly 卡片展示 "BEST VALUE"
- CTA 使用品牌主色
- Paywall 背景使用轻模糊或渐变

## 必要埋点
- paywall_view(source)
- purchase_start(product_id)
- purchase_success(product_id, price, currency)
- restore_success
