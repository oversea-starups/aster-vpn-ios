import Foundation

enum SingBoxConfigurationError: LocalizedError, Equatable {
    case invalidNode(String)
    case unsupportedTransport(String)
    case invalidProtocolConfiguration
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case let .invalidNode(message):
            return message
        case let .unsupportedTransport(transport):
            return "暂不支持 \(transport) 传输方式"
        case .invalidProtocolConfiguration:
            return "节点高级配置格式无效"
        case .encodingFailed:
            return "无法生成 VPN 运行配置"
        }
    }
}

struct SingBoxConfigurationBuilder {
    static func makeConfiguration(for node: VPNNode) throws -> String {
        if let issue = node.configurationIssue {
            throw SingBoxConfigurationError.invalidNode(issue)
        }

        let outbound = try makeOutbound(for: node)
        let configuration: [String: Any] = [
            "log": [
                "level": "warn",
                "timestamp": false,
            ],
            "dns": [
                "servers": [[
                    "type": "udp",
                    "tag": "remote-dns",
                    "server": "1.1.1.1",
                ]],
                "strategy": "prefer_ipv4",
            ],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "mtu": 9_000,
                "auto_route": true,
                "strict_route": true,
                "stack": "gvisor",
            ]],
            "outbounds": [outbound],
            "route": [
                "auto_detect_interface": true,
                "final": "proxy",
                "rules": [[
                    "port": 53,
                    "action": "hijack-dns",
                ]],
            ],
        ]

        guard JSONSerialization.isValidJSONObject(configuration),
              let data = try? JSONSerialization.data(
                withJSONObject: configuration,
                options: [.sortedKeys]
              ),
              let result = String(data: data, encoding: .utf8) else {
            throw SingBoxConfigurationError.encodingFailed
        }
        return result
    }

    private static func makeOutbound(for node: VPNNode) throws -> [String: Any] {
        var outbound: [String: Any] = [
            "type": node.normalizedProtocol,
            "tag": "proxy",
            "server": node.host,
            "server_port": node.port,
        ]

        switch node.normalizedProtocol {
        case "vmess":
            outbound["uuid"] = node.uuid
            outbound["security"] = nonEmpty(node.method) ?? "auto"
            if let alterId = node.alterId, alterId > 0 {
                outbound["alter_id"] = alterId
            }
            outbound["network"] = ["tcp", "udp"]
            outbound["packet_encoding"] = "xudp"
            try applyTLSAndTransport(node: node, to: &outbound)
        case "vless":
            outbound["uuid"] = node.uuid
            outbound["network"] = ["tcp", "udp"]
            outbound["packet_encoding"] = "xudp"
            if let flow = node.protocolString("flow") {
                outbound["flow"] = flow
            }
            try applyTLSAndTransport(node: node, to: &outbound)
        case "anytls":
            outbound["password"] = node.password
            if let value = node.protocolString("idleSessionCheckInterval") {
                outbound["idle_session_check_interval"] = value
            }
            if let value = node.protocolString("idleSessionTimeout") {
                outbound["idle_session_timeout"] = value
            }
            if let value = node.protocolInt("minIdleSession") {
                outbound["min_idle_session"] = value
            }
            outbound["tls"] = makeTLS(node: node, forceEnabled: true)
        default:
            throw SingBoxConfigurationError.invalidNode(
                "暂不支持 \(node.protocolName) 协议"
            )
        }

        return outbound
    }

    private static func applyTLSAndTransport(
        node: VPNNode,
        to outbound: inout [String: Any]
    ) throws {
        let hasReality = node.protocolString("publicKey", "realityPublicKey") != nil
        if node.tls || hasReality {
            outbound["tls"] = makeTLS(node: node, forceEnabled: true)
        }

        switch node.network.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "tcp":
            break
        case "ws", "websocket":
            var transport: [String: Any] = [
                "type": "ws",
                "path": nonEmpty(node.webSocketPath) ?? "/",
            ]
            if let host = node.protocolString("wsHost") {
                transport["headers"] = ["Host": host]
            }
            outbound["transport"] = transport
        case "grpc":
            guard let serviceName = nonEmpty(node.grpcServiceName) else {
                throw SingBoxConfigurationError.invalidNode(
                    "gRPC 节点缺少服务名"
                )
            }
            outbound["transport"] = [
                "type": "grpc",
                "service_name": serviceName,
            ]
        default:
            throw SingBoxConfigurationError.unsupportedTransport(node.network)
        }
    }

    private static func makeTLS(
        node: VPNNode,
        forceEnabled: Bool
    ) -> [String: Any] {
        var tls: [String: Any] = ["enabled": forceEnabled || node.tls]
        tls["server_name"] = node.protocolString("serverName", "sni") ?? node.host

        if let insecure = node.protocolBool(
            "allowInsecure",
            "skipCertVerify",
            "skip-cert-verify"
        ) {
            tls["insecure"] = insecure
        }
        if let alpn = node.protocolStrings("alpn"), !alpn.isEmpty {
            tls["alpn"] = alpn
        }
        if let fingerprint = node.protocolString(
            "clientFingerprint",
            "client-fingerprint",
            "fingerprint"
        ) {
            tls["utls"] = [
                "enabled": true,
                "fingerprint": fingerprint,
            ]
        }
        if let publicKey = node.protocolString("publicKey", "realityPublicKey") {
            var reality: [String: Any] = [
                "enabled": true,
                "public_key": publicKey,
            ]
            if let shortID = node.protocolString("shortId", "shortID") {
                reality["short_id"] = shortID
            }
            tls["reality"] = reality
            if tls["utls"] == nil {
                tls["utls"] = [
                    "enabled": true,
                    "fingerprint": "chrome",
                ]
            }
        }
        return tls
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension VPNNode {
    var protocolObject: [String: JSONValue] {
        guard case let .object(value) = protocolConfiguration else {
            return [:]
        }
        return value
    }

    func protocolString(_ keys: String...) -> String? {
        for key in keys {
            guard case let .string(value)? = protocolObject[key] else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    func protocolBool(_ keys: String...) -> Bool? {
        for key in keys {
            switch protocolObject[key] {
            case let .bool(value): return value
            case let .string(value):
                if value.lowercased() == "true" { return true }
                if value.lowercased() == "false" { return false }
            default: continue
            }
        }
        return nil
    }

    func protocolInt(_ keys: String...) -> Int? {
        for key in keys {
            switch protocolObject[key] {
            case let .number(value): return Int(value)
            case let .string(value):
                if let result = Int(value) { return result }
            default: continue
            }
        }
        return nil
    }

    func protocolStrings(_ keys: String...) -> [String]? {
        for key in keys {
            guard case let .array(values)? = protocolObject[key] else { continue }
            return values.compactMap { value in
                guard case let .string(string) = value else { return nil }
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        return nil
    }
}
