import Foundation

public enum SingBoxConfigurationBuilder {
    public static func makeJSON(from configuration: TunnelConfiguration) throws -> String {
        let config = try configuration.validated()

        var outbound: [String: Any] = [
            "type": config.protocolKind.rawValue,
            "tag": "proxy",
            "server": config.serverAddress,
            "server_port": config.serverPort
        ]

        switch config.protocolKind {
        case .vless:
            outbound["uuid"] = config.uuid
            if let flow = config.flow {
                outbound["flow"] = flow
            }
        case .vmess:
            outbound["uuid"] = config.uuid
            outbound["security"] = config.vmessSecurity
            outbound["alter_id"] = config.vmessAlterID
        case .anytls:
            outbound["password"] = config.anyTLSPassword
        }

        if config.tlsEnabled, let serverName = config.serverName {
            var tls: [String: Any] = [
                "enabled": true,
                "server_name": serverName
            ]
            if let fingerprint = config.tlsFingerprint {
                tls["utls"] = [
                    "enabled": true,
                    "fingerprint": fingerprint
                ]
            }
            if !config.tlsALPN.isEmpty {
                tls["alpn"] = config.tlsALPN
            }
            if let publicKey = config.realityPublicKey {
                var reality: [String: Any] = [
                    "enabled": true,
                    "public_key": publicKey
                ]
                if let shortID = config.realityShortID {
                    reality["short_id"] = shortID
                }
                tls["reality"] = reality
            }
            outbound["tls"] = tls
        }

        if config.transport == .websocket, let path = config.websocketPath {
            var transport: [String: Any] = [
                "type": "ws",
                "path": path
            ]
            if !config.websocketHeaders.isEmpty {
                transport["headers"] = config.websocketHeaders
            }
            outbound["transport"] = transport
        } else if config.transport == .grpc {
            var transport: [String: Any] = ["type": "grpc"]
            if let serviceName = config.grpcServiceName, !serviceName.isEmpty {
                transport["service_name"] = serviceName
            }
            outbound["transport"] = transport
        }

        let root: [String: Any] = [
            "log": ["level": "error"],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "interface_name": "utun",
                "address": ["172.19.0.1/30"],
                "auto_route": true,
                "strict_route": true
            ]],
            "outbounds": [outbound],
            "route": ["final": "proxy"]
        ]

        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw TunnelConfigError.corruptConfiguration
        }
        return json
    }
}
