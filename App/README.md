# Aster VPN iOS

原生 iPhone 客户端工程，包含 SwiftUI App、`NETunnelProviderManager` 管理层和 Packet Tunnel Network Extension。

## 工程生成

工程结构以 `project.yml` 为事实来源，使用 Swift 编写的 XcodeGen 生成；不要手工修改 `project.pbxproj`：

```bash
cd apps/ios
xcodegen generate --spec project.yml
```

## 本地配置

- Debug API 默认指向 `http://127.0.0.1:3001`，可通过 Scheme 环境变量 `ASTER_API_BASE_URL` 覆盖。
- Release 已配置生产 HTTPS API 与公开法律/支持 URL；归档前仍需做可用性回查。
- App Bundle ID：`com.astervpn.Aster`
- Packet Tunnel Bundle ID：`com.astervpn.Aster.PacketTunnel`
- App Group：`group.com.astervpn.shared`

Bundle ID 和 App Group 必须在 Apple Developer 组织账号中注册，并为 App 与 Extension 启用 Network Extensions capability。仓库不保存 Team ID、证书或 provisioning profile。

## VPN 数据面

Packet Tunnel 已固定接入 `AsterLibbox 1.13.16-aster.1`，支持 VMess、VLESS（含 Reality/XTLS）和 AnyTLS；WireGuard 延后。配置由 App 写入共享 Keychain，Extension 启动时在内存中生成 sing-box 配置，不把节点密码、UUID 或 Reality 参数写入系统 VPN preferences 或日志。

依赖源码、构建脚本、许可证告知和 XCFramework 发布在 [`oversea-starups/aster-vpn-ios`](https://github.com/oversea-starups/aster-vpn-ios)。该数据面包含 GPL-3.0-or-later 组件；任何 App Store 分发前必须保持完整对应源码可得，并完成最终许可证/App Store 条款法律审查。

当前已完成无签名 device 编译、三类真实节点配置校验和经同一 outbound 配置的实际出网测试。真实 iPhone 上的首连授权、DNS/IPv6、Wi-Fi/蜂窝切换、锁屏/唤醒和重连仍是提交前验收项。
