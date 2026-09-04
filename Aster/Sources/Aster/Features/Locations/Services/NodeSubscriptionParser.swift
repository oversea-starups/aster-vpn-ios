import CryptoKit
import Foundation

struct NodeSubscriptionParseResult: Equatable {
    let nodes: [VPNNode]
    let discardedEntryCount: Int
}

struct NodeSubscriptionParser {
    static let maximumPayloadBytes = 1_048_576
    static let maximumNodes = 200

    func parse(_ data: Data) throws -> NodeSubscriptionParseResult {
        guard !data.isEmpty, data.count <= Self.maximumPayloadBytes else {
            throw NodeSubscriptionError.invalidPayload
        }
        guard let rawText = String(data: data, encoding: .utf8) else {
            throw NodeSubscriptionError.invalidPayload
        }

        let text = try decodedSubscriptionText(rawText)
        let entries = text
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !entries.isEmpty else {
            throw NodeSubscriptionError.noSupportedLocations
        }

        var nodes: [VPNNode] = []
        var nodeIDs = Set<String>()
        var discarded = 0

        for (index, entry) in entries.enumerated() {
            guard nodes.count < Self.maximumNodes else {
                discarded += 1
                continue
            }
            do {
                let node: VPNNode
                if entry.lowercased().hasPrefix("anytls://") {
                    node = try parseAnyTLS(entry, position: index + 1)
                } else if entry.lowercased().hasPrefix("vless://") {
                    node = try parseVLESS(entry, position: index + 1)
                } else if entry.lowercased().hasPrefix("vmess://") {
                    node = try parseVMess(entry, position: index + 1)
                } else {
                    discarded += 1
                    continue
                }

                let validated = try node.validated()
                if nodeIDs.insert(validated.id).inserted {
                    nodes.append(validated)
                } else {
                    discarded += 1
                }
            } catch {
                discarded += 1
            }
        }

        guard !nodes.isEmpty else {
            throw NodeSubscriptionError.noSupportedLocations
        }
        return NodeSubscriptionParseResult(nodes: nodes, discardedEntryCount: discarded)
    }

    private func decodedSubscriptionText(_ rawText: String) throws -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"(?i)(?:anytls|vless|vmess)://"#, options: .regularExpression) != nil {
            return trimmed
        }

        let compact = trimmed.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard
            let decoded = Self.decodeBase64(String(String.UnicodeScalarView(compact))),
            decoded.count <= Self.maximumPayloadBytes,
            let text = String(data: decoded, encoding: .utf8),
            text.range(of: #"(?i)(?:anytls|vless|vmess)://"#, options: .regularExpression) != nil
        else {
            throw NodeSubscriptionError.invalidPayload
        }
        return text
    }

    private func parseVLESS(_ entry: String, position: Int) throws -> VPNNode {
        guard
            let components = URLComponents(string: entry),
            components.scheme?.lowercased() == "vless",
            let uuid = components.user,
            let host = components.host,
            let port = components.port
        else {
            throw NodeSubscriptionError.invalidEntry
        }

        let query = try queryDictionary(components.queryItems ?? [])
        guard query["encryption", default: "none"].lowercased() == "none" else {
            throw NodeSubscriptionError.unsupportedEntry
        }

        let transport = try parseTransport(query["type"])
        let security = query["security", default: "none"].lowercased()
        let tlsEnabled: Bool
        let tlsInsecure: Bool
        let realityPublicKey: String?
        switch security {
        case "", "none":
            // VLESS itself does not encrypt the transport. Accepting a new
            // subscription entry without TLS/Reality would contradict the
            // product's public-network protection promise.
            throw NodeSubscriptionError.insecureEntry
        case "tls":
            tlsEnabled = true
            // Never weaken ordinary TLS entries. Some Reality subscriptions
            // explicitly require this compatibility flag, handled below.
            if Self.truthy(query["allowinsecure"]) || Self.truthy(query["insecure"]) {
                throw NodeSubscriptionError.insecureEntry
            }
            tlsInsecure = false
            realityPublicKey = nil
        case "reality":
            tlsEnabled = true
            guard let publicKey = query["pbk"], !publicKey.isEmpty else {
                throw NodeSubscriptionError.invalidEntry
            }
            tlsInsecure = Self.truthy(query["allowinsecure"]) || Self.truthy(query["insecure"])
            realityPublicKey = publicKey
        default:
            throw NodeSubscriptionError.unsupportedEntry
        }

        let rawDisplayName = Self.displayName(
            preferred: components.fragment,
            fallback: "Secure Location \(position)"
        )
        guard !VPNNode.isStatusRecord(rawDisplayName) else {
            throw NodeSubscriptionError.statusEntry
        }
        let displayName = String(VPNNode.regionName(from: rawDisplayName).prefix(80))
        let serverName = tlsEnabled
            ? Self.firstNonEmpty(query["sni"], query["servername"], host)
            : nil
        let websocketPath = transport == .websocket
            ? Self.normalizedPath(query["path"])
            : nil
        let websocketHeaders = transport == .websocket
            ? Self.hostHeader(query["host"])
            : [:]
        let grpcServiceName = transport == .grpc
            ? Self.normalizedServiceName(Self.firstNonEmpty(query["servicename"], query["service_name"], query["path"]))
            : nil
        let flow = Self.nilIfEmpty(query["flow"]?.lowercased())
        let fingerprint = Self.nilIfEmpty(query["fp"]?.lowercased())
        let alpn = Self.parseALPN(query["alpn"])
        let canonical = [
            "vless", host.lowercased(), String(port), uuid.lowercased(),
            transport.rawValue, security, serverName?.lowercased() ?? "",
            websocketPath ?? "", grpcServiceName ?? "", flow ?? "",
            realityPublicKey ?? "", query["sid"]?.lowercased() ?? "",
            fingerprint ?? "", alpn.joined(separator: ","), tlsInsecure ? "1" : "0"
        ].joined(separator: "\u{1f}")
        let nodeID = Self.stableNodeID(canonical)

        return VPNNode(
            id: nodeID,
            displayName: displayName,
            configuration: TunnelConfiguration(
                nodeID: nodeID,
                serverAddress: host,
                serverPort: port,
                uuid: uuid,
                protocolKind: .vless,
                transport: transport,
                tlsEnabled: tlsEnabled,
                tlsInsecure: tlsInsecure,
                serverName: serverName,
                websocketPath: websocketPath,
                websocketHeaders: websocketHeaders,
                grpcServiceName: grpcServiceName,
                flow: flow,
                realityPublicKey: realityPublicKey,
                realityShortID: realityPublicKey == nil ? nil : query["sid"],
                tlsFingerprint: fingerprint,
                tlsALPN: alpn
            )
        )
    }

    private func parseAnyTLS(_ entry: String, position: Int) throws -> VPNNode {
        guard
            let components = URLComponents(string: entry),
            components.scheme?.lowercased() == "anytls",
            let password = components.user,
            !password.isEmpty,
            let host = components.host,
            let port = components.port
        else {
            throw NodeSubscriptionError.invalidEntry
        }

        let query = try queryDictionary(components.queryItems ?? [])
        guard query["security", default: "tls"].lowercased() == "tls" else {
            throw NodeSubscriptionError.insecureEntry
        }
        if Self.truthy(query["allowinsecure"]) || Self.truthy(query["insecure"]) {
            throw NodeSubscriptionError.insecureEntry
        }
        let rawDisplayName = Self.displayName(
            preferred: components.fragment,
            fallback: "Secure Location \(position)"
        )
        guard !VPNNode.isStatusRecord(rawDisplayName) else {
            throw NodeSubscriptionError.statusEntry
        }
        let displayName = String(VPNNode.regionName(from: rawDisplayName).prefix(80))
        let serverName = Self.firstNonEmpty(query["sni"], query["servername"], host)
        let fingerprint = Self.nilIfEmpty(query["fp"]?.lowercased())
        let alpn = Self.parseALPN(query["alpn"])
        let canonical = [
            "anytls", host.lowercased(), String(port), password,
            serverName?.lowercased() ?? "", fingerprint ?? "",
            alpn.joined(separator: ",")
        ].joined(separator: "\u{1f}")
        let nodeID = Self.stableNodeID(canonical)

        return VPNNode(
            id: nodeID,
            displayName: displayName,
            configuration: TunnelConfiguration(
                nodeID: nodeID,
                serverAddress: host,
                serverPort: port,
                uuid: "00000000-0000-0000-0000-000000000000",
                protocolKind: .anytls,
                transport: .tcp,
                tlsEnabled: true,
                serverName: serverName,
                tlsFingerprint: fingerprint,
                tlsALPN: alpn,
                anyTLSPassword: password
            )
        )
    }

    private func parseVMess(_ entry: String, position: Int) throws -> VPNNode {
        let payloadText = String(entry.dropFirst("vmess://".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let data = Self.decodeBase64(payloadText),
            data.count <= 65_536,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw NodeSubscriptionError.invalidEntry
        }

        guard
            let host = Self.stringValue(object["add"]),
            let port = Self.intValue(object["port"]),
            let uuid = Self.stringValue(object["id"])
        else {
            throw NodeSubscriptionError.invalidEntry
        }
        let transport = try parseTransport(Self.stringValue(object["net"]))
        let tlsValue = Self.stringValue(object["tls"])?.lowercased() ?? ""
        let tlsEnabled: Bool
        switch tlsValue {
        case "", "none": tlsEnabled = false
        case "tls": tlsEnabled = true
        default: throw NodeSubscriptionError.unsupportedEntry
        }
        if Self.truthy(Self.stringValue(object["allowInsecure"])) {
            throw NodeSubscriptionError.insecureEntry
        }

        let rawDisplayName = Self.displayName(
            preferred: Self.stringValue(object["ps"]),
            fallback: "Secure Location \(position)"
        )
        guard !VPNNode.isStatusRecord(rawDisplayName) else {
            throw NodeSubscriptionError.statusEntry
        }
        let displayName = String(VPNNode.regionName(from: rawDisplayName).prefix(80))
        let vmessSecurity = Self.stringValue(object["scy"])?.lowercased() ?? "auto"
        if !tlsEnabled, vmessSecurity == "none" || vmessSecurity == "zero" {
            throw NodeSubscriptionError.insecureEntry
        }
        let vmessAlterID = Self.intValue(object["aid"]) ?? 0
        let serverName = tlsEnabled
            ? Self.firstNonEmpty(Self.stringValue(object["sni"]), Self.stringValue(object["host"]), host)
            : nil
        let websocketPath = transport == .websocket
            ? Self.normalizedPath(Self.stringValue(object["path"]))
            : nil
        let websocketHeaders = transport == .websocket
            ? Self.hostHeader(Self.stringValue(object["host"]))
            : [:]
        let grpcServiceName = transport == .grpc
            ? Self.normalizedServiceName(Self.stringValue(object["path"]))
            : nil
        let fingerprint = Self.nilIfEmpty(Self.stringValue(object["fp"])?.lowercased())
        let canonical = [
            "vmess", host.lowercased(), String(port), uuid.lowercased(),
            transport.rawValue, tlsValue, serverName?.lowercased() ?? "",
            websocketPath ?? "", grpcServiceName ?? "", vmessSecurity, String(vmessAlterID)
        ].joined(separator: "\u{1f}")
        let nodeID = Self.stableNodeID(canonical)

        return VPNNode(
            id: nodeID,
            displayName: displayName,
            configuration: TunnelConfiguration(
                nodeID: nodeID,
                serverAddress: host,
                serverPort: port,
                uuid: uuid,
                protocolKind: .vmess,
                transport: transport,
                tlsEnabled: tlsEnabled,
                serverName: serverName,
                websocketPath: websocketPath,
                websocketHeaders: websocketHeaders,
                grpcServiceName: grpcServiceName,
                tlsFingerprint: fingerprint,
                vmessSecurity: vmessSecurity,
                vmessAlterID: vmessAlterID
            )
        )
    }

    private func parseTransport(_ value: String?) throws -> TunnelConfiguration.Transport {
        switch value?.lowercased() ?? "tcp" {
        case "", "tcp": return .tcp
        case "ws", "websocket": return .websocket
        case "grpc": return .grpc
        default: throw NodeSubscriptionError.unsupportedEntry
        }
    }

    private func queryDictionary(_ items: [URLQueryItem]) throws -> [String: String] {
        var result: [String: String] = [:]
        for item in items {
            let key = item.name.lowercased()
            guard result[key] == nil else {
                throw NodeSubscriptionError.invalidEntry
            }
            result[key] = item.value ?? ""
        }
        return result
    }

    private static func stableNodeID(_ canonical: String) -> String {
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return "node-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func decodeBase64(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .filter { !$0.isWhitespace }
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: normalized)
    }

    private static func displayName(preferred: String?, fallback: String) -> String {
        let clean = (preferred ?? "")
            .unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((clean.isEmpty ? fallback : clean).prefix(80))
    }

    private static func normalizedPath(_ value: String?) -> String {
        guard let value = nilIfEmpty(value) else { return "/" }
        return value.hasPrefix("/") ? value : "/\(value)"
    }

    private static func normalizedServiceName(_ value: String?) -> String? {
        nilIfEmpty(value?.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private static func hostHeader(_ value: String?) -> [String: String] {
        guard let value = nilIfEmpty(value?.split(separator: ",").first.map(String.init)) else {
            return [:]
        }
        return ["Host": value]
    }

    private static func parseALPN(_ value: String?) -> [String] {
        (value ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap(nilIfEmpty).first
    }

    private static func truthy(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return value == "1" || value == "true" || value == "yes"
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String: return nilIfEmpty(value)
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int: return value
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value)
        default: return nil
        }
    }
}

enum NodeSubscriptionError: Error, LocalizedError, Equatable {
    case invalidPayload
    case noSupportedLocations
    case invalidEntry
    case unsupportedEntry
    case insecureEntry
    case statusEntry

    var errorDescription: String? {
        switch self {
        case .invalidPayload, .noSupportedLocations, .invalidEntry, .unsupportedEntry, .insecureEntry, .statusEntry:
            return "Aster couldn't verify any compatible VPN locations from the update."
        }
    }
}
