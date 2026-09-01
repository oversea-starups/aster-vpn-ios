# SPEC-0053 — Demo 防滥用策略

## 方案 A（纯客户端）
- 首次启动一次性 60 秒
- 使用 Keychain 持久化标记
- 缺点：仍可卸载重装绕过

## 方案 B（推荐）
- App 启动时向服务端记录 device_id hash
- 服务端只允许一次 demo token

## 结论
- MVP 可先用 A
- 若滥用严重，升级到 B
