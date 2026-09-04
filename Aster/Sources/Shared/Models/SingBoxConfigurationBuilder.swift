import Foundation

public enum SingBoxConfigurationBuilder {
    public static func makeJSON(from configuration: TunnelConfiguration) throws -> String {
        let config = try configuration.validated()

        var outbound: [String: Any] = [
            "type": config.protocolKind.rawValue,
            "tag": "proxy",
            // The app resolves the endpoint before iOS enables the exclusive
            // full-tunnel policy. Keep the original hostname in `server_name`
            // below for certificate/SNI validation, but dial the numeric
            // address so sing-box never needs a circular DNS lookup for its
            // own proxy endpoint inside the tunnel.
            "server": config.resolvedServerAddresses.first ?? config.serverAddress,
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
            if config.tlsInsecure {
                // Only VLESS Reality nodes may opt into this compatibility
                // flag; validation rejects it for ordinary TLS/other protocols.
                tls["insecure"] = true
            }
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

        #if DEBUG
        let logLevel = "debug"
        #else
        let logLevel = "error"
        #endif

        let root: [String: Any] = [
            "log": ["level": logLevel],
            // Resolve names inside the tunnel. Without an explicit DNS route,
            // iOS can resolve a hostname outside the proxy while the tun
            // stack is coming up, then hand sing-box an unreachable address.
            // The catalog's AnyTLS/VLESS/VMess entries are TCP outbounds, so
            // UDP DNS can silently fail even while the tunnel reports ready.
            // Use TCP DNS and explicitly detour it through the selected proxy;
            // the literal resolver IP avoids a bootstrap hostname dependency.
            // Hijacking port 53 keeps app DNS requests on this same path.
            "dns": [
                "servers": [[
                    "type": "tcp",
                    "tag": "remote-dns",
                    "server": "1.1.1.1",
                    "server_port": 53,
                    "detour": "proxy"
                ]],
                "strategy": "prefer_ipv4"
            ],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "interface_name": "utun",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                // iOS rejects jumbo TUN MTUs (the device log reports
                // `Invalid argument` for 9000). Keep the tunnel within the
                // platform-supported Ethernet MTU so Network Extension can
                // finish bringing the interface up.
                "mtu": 1500,
                "stack": "gvisor",
                "auto_route": true,
                "strict_route": true
            ]],
            "outbounds": [outbound],
            "route": [
                "auto_detect_interface": true,
                "final": "proxy",
                // AnyTLS, VLESS and VMess entries in the catalog expose a TCP
                // data plane. iOS browsers will otherwise optimistically send
                // HTTP/3 over UDP/443; passing that unsupported datagram to a
                // TCP-only outbound leaves Safari waiting for QUIC retries and
                // makes a healthy TCP tunnel look unusable. Rejecting QUIC's
                // well-known port makes clients immediately fall back to TCP.
                "rules": [
                    [
                        "port": 53,
                        "action": "hijack-dns"
                    ],
                    [
                        "protocol": "quic",
                        "action": "reject"
                    ],
                    [
                        "network": "udp",
                        "port": 443,
                        "action": "reject"
                    ],
                    [
                        // Some exits or upstream networks close a large TLS
                        // ClientHello before returning ServerHello. Split
                        // the first TLS record on the proxied leg while
                        // leaving the established stream untouched.
                        "action": "route-options",
                        "tls_record_fragment": true
                    ]
                ]
            ] as [String: Any]
        ]

        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw TunnelConfigError.corruptConfiguration
        }
        return json
    }
}
