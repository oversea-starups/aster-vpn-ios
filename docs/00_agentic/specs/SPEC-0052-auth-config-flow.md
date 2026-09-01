# SPEC-0052 — 订阅鉴权与配置下发流程（最小后端）

## 目标
确保订阅用户才能获取 Pro 配置。

## 流程
1. App 购买成功 → 获取 receipt
2. App 请求验证接口（server）
3. server 验证 Apple receipt
4. server 返回授权 token + Pro 配置

## MVP 方案
- 使用轻量 Serverless（Cloudflare Workers / Vercel）
- 只存订阅状态与过期时间

## 无后端替代（风险）
- 仅本地解锁 Pro → 易被绕过
