# SPEC-0051 — 协议与配置下发（VLESS/VMess）

## 当前协议
- 自建：VLESS + VMess
- 第三方：VMess

## 配置结构（建议）
- base64 JSON 或订阅链接解析
- 最小字段：address, port, id(uuid), security, tls, sni, path, host, alterId, network

## 配置下发方式
- MVP：App 内置基础节点（免费节点）+ 远程更新 Pro 节点
- 远程配置：Remote Config / 加密配置文件（HTTPS + 签名）

## 安全要求
- 配置需签名校验
- Pro 节点需订阅状态校验后才可下发
