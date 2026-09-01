# SPEC-0032 — 配置与密钥（规划）

## 本地配置
- Locations.json（节点列表）
- RemoteConfigDefaults.plist
- StoreKitConfig.storekit

## 机密配置（不进仓库）
- VPN Provider Key
- 自建节点配置（3x-ui 导出）

## 规则
- 机密配置使用 .gitignore
- 重要密钥仅在 CI/本地注入
