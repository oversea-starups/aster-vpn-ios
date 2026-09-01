import Foundation

public struct VPNNode: Codable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let configuration: TunnelConfiguration

    public init(id: String, displayName: String, configuration: TunnelConfiguration) {
        self.id = id
        self.displayName = displayName
        self.configuration = configuration
    }

    public func validated() throws -> VPNNode {
        guard
            !id.isEmpty,
            id.count <= 128,
            id == configuration.nodeID,
            !displayName.isEmpty,
            displayName.count <= 80,
            !displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw VPNNodeError.invalidMetadata
        }
        return VPNNode(
            id: id,
            displayName: displayName,
            configuration: try configuration.validated()
        )
    }

    public func matchesConnection(_ other: TunnelConfiguration) -> Bool {
        guard let lhs = try? configuration.validated(), let rhs = try? other.validated() else {
            return false
        }
        return lhs.serverAddress.caseInsensitiveCompare(rhs.serverAddress) == .orderedSame &&
            lhs.serverPort == rhs.serverPort &&
            lhs.uuid.caseInsensitiveCompare(rhs.uuid) == .orderedSame &&
            lhs.protocolKind == rhs.protocolKind &&
            lhs.transport == rhs.transport &&
            lhs.tlsEnabled == rhs.tlsEnabled &&
            lhs.serverName?.lowercased() == rhs.serverName?.lowercased() &&
            lhs.websocketPath == rhs.websocketPath &&
            lhs.websocketHeaders == rhs.websocketHeaders &&
            lhs.grpcServiceName == rhs.grpcServiceName &&
            lhs.flow == rhs.flow &&
            lhs.realityPublicKey == rhs.realityPublicKey &&
            lhs.realityShortID?.lowercased() == rhs.realityShortID?.lowercased() &&
            lhs.tlsFingerprint == rhs.tlsFingerprint &&
            lhs.tlsALPN == rhs.tlsALPN &&
            lhs.vmessSecurity == rhs.vmessSecurity &&
            lhs.vmessAlterID == rhs.vmessAlterID &&
            lhs.anyTLSPassword == rhs.anyTLSPassword
    }

    public var protocolLabel: String {
        configuration.protocolKind.rawValue.uppercased()
    }

    /// Provider labels can include plan tiers, server numbers, and protocol hints.
    /// The app only presents a stable region label; the complete connection fields
    /// remain in `configuration` for the tunnel engine.
    public var regionName: String {
        Self.regionName(from: displayName)
    }

    public static func regionName(from value: String) -> String {
        let normalized = value.lowercased()
        let regions: [(String, [String])] = [
            ("Hong Kong", ["🇭🇰", "hong kong", "香港", "hk", "hkg"]),
            ("United States", ["🇺🇸", "united states", "usa", "美国", "us"]),
            ("Japan", ["🇯🇵", "japan", "日本", "jp", "jpn"]),
            ("Singapore", ["🇸🇬", "singapore", "新加坡", "sg", "sgp"]),
            ("Taiwan", ["🇹🇼", "taiwan", "台湾", "台灣", "tw", "twn"]),
            ("Germany", ["🇩🇪", "germany", "德国", "德國", "de", "deu"])
        ]

        for (name, markers) in regions {
            if markers.contains(where: { marker in
                if marker.count <= 3, marker.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
                    let tokens = normalized.components(separatedBy: CharacterSet.letters.inverted)
                    return tokens.contains(where: { $0 == marker })
                }
                return normalized.contains(marker)
            }) {
                return name
            }
        }

        if normalized.contains("家") || normalized.contains("home") {
            return "Home"
        }
        return "Available location"
    }

    public static func isStatusRecord(_ value: String) -> Bool {
        let normalized = value.lowercased()
        let markers = [
            "剩余流量", "套餐到期", "到期时间", "有效期", "流量重置", "重置时间",
            "traffic remaining", "data remaining", "plan expiry", "subscription expiry",
            "expires", "expiration", "valid until"
        ]
        return markers.contains(where: normalized.contains)
    }
}

public struct NodeCatalogSnapshot: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let updatedAt: Date
    public let nodes: [VPNNode]

    public init(
        schemaVersion: Int = NodeCatalogSnapshot.currentSchemaVersion,
        updatedAt: Date,
        nodes: [VPNNode]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.nodes = nodes
    }

    public func validated(maximumNodes: Int = 200) throws -> NodeCatalogSnapshot {
        guard schemaVersion == Self.currentSchemaVersion, !nodes.isEmpty, nodes.count <= maximumNodes else {
            throw VPNNodeError.invalidCatalog
        }
        var ids = Set<String>()
        var validatedNodes: [VPNNode] = []
        for node in nodes {
            let node = try node.validated()
            guard ids.insert(node.id).inserted else {
                throw VPNNodeError.duplicateNode
            }
            validatedNodes.append(node)
        }
        return NodeCatalogSnapshot(updatedAt: updatedAt, nodes: validatedNodes)
    }
}

public enum VPNNodeError: Error, LocalizedError, Equatable {
    case invalidMetadata
    case invalidCatalog
    case duplicateNode

    public var errorDescription: String? {
        "The VPN location list couldn't be verified."
    }
}
