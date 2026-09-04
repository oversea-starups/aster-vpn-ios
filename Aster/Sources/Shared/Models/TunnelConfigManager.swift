import Foundation
import Darwin

public struct TunnelConfiguration: Codable, Equatable {
    public static let currentSchemaVersion = 2

    public enum ProtocolKind: String, Codable, CaseIterable {
        case vless
        case vmess
        case anytls
    }

    public enum Transport: String, Codable, CaseIterable {
        case tcp
        case websocket
        case grpc
    }

    public let schemaVersion: Int
    public let nodeID: String
    public let serverAddress: String
    public let serverPort: Int
    public let uuid: String
    public let protocolKind: ProtocolKind
    public let transport: Transport
    public let tlsEnabled: Bool
    /// Explicitly preserve the Reality subscription's certificate-compatibility
    /// flag without weakening ordinary TLS nodes.
    public let tlsInsecure: Bool
    public let serverName: String?
    public let websocketPath: String?
    public let websocketHeaders: [String: String]
    public let grpcServiceName: String?
    public let flow: String?
    public let realityPublicKey: String?
    public let realityShortID: String?
    public let tlsFingerprint: String?
    public let tlsALPN: [String]
    public let vmessSecurity: String
    public let vmessAlterID: Int
    /// Password used by the AnyTLS protocol. It is intentionally separate
    /// from `uuid` because AnyTLS credentials are not UUIDs.
    public let anyTLSPassword: String
    /// Numeric addresses resolved by the app before the full-tunnel policy is
    /// enabled. The original `serverAddress` remains the TLS/SNI name while
    /// these values keep the proxy endpoint reachable outside the TUN route.
    /// This is derived connection state and is intentionally optional for
    /// backwards compatibility with existing App Group configurations.
    public let resolvedServerAddresses: [String]

    public init(
        schemaVersion: Int = TunnelConfiguration.currentSchemaVersion,
        nodeID: String,
        serverAddress: String,
        serverPort: Int,
        uuid: String,
        protocolKind: ProtocolKind = .vless,
        transport: Transport = .tcp,
        tlsEnabled: Bool = true,
        tlsInsecure: Bool = false,
        serverName: String? = nil,
        websocketPath: String? = nil,
        websocketHeaders: [String: String] = [:],
        grpcServiceName: String? = nil,
        flow: String? = nil,
        realityPublicKey: String? = nil,
        realityShortID: String? = nil,
        tlsFingerprint: String? = nil,
        tlsALPN: [String] = [],
        vmessSecurity: String = "auto",
        vmessAlterID: Int = 0,
        anyTLSPassword: String = "",
        resolvedServerAddresses: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.nodeID = nodeID
        self.serverAddress = serverAddress
        self.serverPort = serverPort
        self.uuid = uuid
        self.protocolKind = protocolKind
        self.transport = transport
        self.tlsEnabled = tlsEnabled
        self.tlsInsecure = tlsInsecure
        self.serverName = serverName
        self.websocketPath = websocketPath
        self.websocketHeaders = websocketHeaders
        self.grpcServiceName = grpcServiceName
        self.flow = flow
        self.realityPublicKey = realityPublicKey
        self.realityShortID = realityShortID
        self.tlsFingerprint = tlsFingerprint
        self.tlsALPN = tlsALPN
        self.vmessSecurity = vmessSecurity
        self.vmessAlterID = vmessAlterID
        self.anyTLSPassword = anyTLSPassword
        self.resolvedServerAddresses = resolvedServerAddresses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        nodeID = try container.decode(String.self, forKey: .nodeID)
        serverAddress = try container.decode(String.self, forKey: .serverAddress)
        serverPort = try container.decode(Int.self, forKey: .serverPort)
        uuid = try container.decode(String.self, forKey: .uuid)
        protocolKind = try container.decodeIfPresent(ProtocolKind.self, forKey: .protocolKind) ?? .vless
        transport = try container.decodeIfPresent(Transport.self, forKey: .transport) ?? .tcp
        tlsEnabled = try container.decodeIfPresent(Bool.self, forKey: .tlsEnabled) ?? true
        tlsInsecure = try container.decodeIfPresent(Bool.self, forKey: .tlsInsecure) ?? false
        serverName = try container.decodeIfPresent(String.self, forKey: .serverName)
        websocketPath = try container.decodeIfPresent(String.self, forKey: .websocketPath)
        websocketHeaders = try container.decodeIfPresent([String: String].self, forKey: .websocketHeaders) ?? [:]
        grpcServiceName = try container.decodeIfPresent(String.self, forKey: .grpcServiceName)
        flow = try container.decodeIfPresent(String.self, forKey: .flow)
        realityPublicKey = try container.decodeIfPresent(String.self, forKey: .realityPublicKey)
        realityShortID = try container.decodeIfPresent(String.self, forKey: .realityShortID)
        tlsFingerprint = try container.decodeIfPresent(String.self, forKey: .tlsFingerprint)
        tlsALPN = try container.decodeIfPresent([String].self, forKey: .tlsALPN) ?? []
        vmessSecurity = try container.decodeIfPresent(String.self, forKey: .vmessSecurity) ?? "auto"
        vmessAlterID = try container.decodeIfPresent(Int.self, forKey: .vmessAlterID) ?? 0
        anyTLSPassword = try container.decodeIfPresent(String.self, forKey: .anyTLSPassword) ?? ""
        resolvedServerAddresses = try container.decodeIfPresent([String].self, forKey: .resolvedServerAddresses) ?? []
    }

    public func validated() throws -> TunnelConfiguration {
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
            throw TunnelConfigError.unsupportedSchema
        }
        guard !nodeID.isEmpty, nodeID.count <= 128 else {
            throw TunnelConfigError.invalidNodeID
        }
        guard
            !serverAddress.isEmpty,
            serverAddress.count <= 253,
            serverAddress.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            })
        else {
            throw TunnelConfigError.invalidServerAddress
        }
        guard resolvedServerAddresses.count <= 32,
              resolvedServerAddresses.allSatisfy(Self.isValidResolvedServerAddress) else {
            throw TunnelConfigError.invalidResolvedServerAddresses
        }
        guard (1...65_535).contains(serverPort) else {
            throw TunnelConfigError.invalidServerPort
        }
        switch protocolKind {
        case .vless, .vmess:
            guard UUID(uuidString: uuid) != nil else {
                throw TunnelConfigError.invalidCredential
            }
        case .anytls:
            guard !anyTLSPassword.isEmpty,
                  anyTLSPassword.count <= 512,
                  !anyTLSPassword.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  transport == .tcp,
                  tlsEnabled else {
                throw TunnelConfigError.invalidAnyTLSSettings
            }
        }
        if tlsEnabled {
            guard let serverName, !serverName.isEmpty, serverName.count <= 253 else {
                throw TunnelConfigError.missingServerName
            }
        }
        if tlsInsecure {
            guard protocolKind == .vless, realityPublicKey != nil, tlsEnabled else {
                throw TunnelConfigError.invalidTLSInsecure
            }
        }
        if transport == .websocket {
            guard let websocketPath, websocketPath.hasPrefix("/"), websocketPath.count <= 2_048 else {
                throw TunnelConfigError.invalidWebSocketPath
            }
            guard websocketHeaders.count <= 16 else {
                throw TunnelConfigError.tooManyHeaders
            }
            guard websocketHeaders.allSatisfy({ key, value in
                !key.isEmpty && key.count <= 256 && value.count <= 2_048 &&
                    !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
                    !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            }) else {
                throw TunnelConfigError.invalidHeader
            }
        }
        if transport == .grpc {
            guard (grpcServiceName?.count ?? 0) <= 1_024 else {
                throw TunnelConfigError.invalidGRPCServiceName
            }
        }
        if let flow {
            guard protocolKind == .vless, flow == "xtls-rprx-vision" else {
                throw TunnelConfigError.invalidFlow
            }
        }
        if let realityPublicKey {
            guard
                protocolKind == .vless,
                tlsEnabled,
                realityPublicKey.range(of: #"^[A-Za-z0-9_-]{40,64}$"#, options: .regularExpression) != nil
            else {
                throw TunnelConfigError.invalidReality
            }
            if let realityShortID {
                guard
                    realityShortID.count <= 16,
                    realityShortID.count.isMultiple(of: 2),
                    realityShortID.range(of: #"^[0-9a-fA-F]*$"#, options: .regularExpression) != nil
                else {
                    throw TunnelConfigError.invalidReality
                }
            }
        }
        if let tlsFingerprint {
            let supported = Set(["chrome", "firefox", "edge", "safari", "360", "qq", "ios", "android", "random", "randomized"])
            guard supported.contains(tlsFingerprint) else {
                throw TunnelConfigError.invalidTLSFingerprint
            }
        }
        guard tlsALPN.count <= 8,
              tlsALPN.allSatisfy({ value in
                  !value.isEmpty && value.count <= 64 &&
                      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
              }) else {
            throw TunnelConfigError.invalidTLSALPN
        }
        if protocolKind == .vmess {
            let supportedSecurity = Set(["auto", "none", "zero", "aes-128-gcm", "chacha20-poly1305", "aes-128-ctr"])
            guard supportedSecurity.contains(vmessSecurity), (0...65_535).contains(vmessAlterID) else {
                throw TunnelConfigError.invalidVMessSettings
            }
            guard flow == nil, realityPublicKey == nil else {
                throw TunnelConfigError.invalidVMessSettings
            }
        }

        return TunnelConfiguration(
            schemaVersion: Self.currentSchemaVersion,
            nodeID: nodeID,
            serverAddress: serverAddress,
            serverPort: serverPort,
            uuid: uuid.lowercased(),
            protocolKind: protocolKind,
            transport: transport,
            tlsEnabled: tlsEnabled,
            tlsInsecure: tlsInsecure,
            serverName: serverName,
            websocketPath: websocketPath,
            websocketHeaders: websocketHeaders,
            grpcServiceName: grpcServiceName,
            flow: flow,
            realityPublicKey: realityPublicKey,
            realityShortID: realityShortID?.lowercased(),
            tlsFingerprint: tlsFingerprint,
            tlsALPN: tlsALPN,
            vmessSecurity: vmessSecurity,
            vmessAlterID: vmessAlterID,
            anyTLSPassword: anyTLSPassword,
            resolvedServerAddresses: resolvedServerAddresses
        )
    }

    /// Returns a copy with the latest pre-resolved endpoint set. The resolver
    /// runs in the app while the physical interface is still available; the
    /// packet tunnel consumes only these numeric values after full-tunnel
    /// routing has been installed.
    public func withResolvedServerAddresses(_ addresses: [String]) -> TunnelConfiguration {
        TunnelConfiguration(
            schemaVersion: schemaVersion,
            nodeID: nodeID,
            serverAddress: serverAddress,
            serverPort: serverPort,
            uuid: uuid,
            protocolKind: protocolKind,
            transport: transport,
            tlsEnabled: tlsEnabled,
            tlsInsecure: tlsInsecure,
            serverName: serverName,
            websocketPath: websocketPath,
            websocketHeaders: websocketHeaders,
            grpcServiceName: grpcServiceName,
            flow: flow,
            realityPublicKey: realityPublicKey,
            realityShortID: realityShortID,
            tlsFingerprint: tlsFingerprint,
            tlsALPN: tlsALPN,
            vmessSecurity: vmessSecurity,
            vmessAlterID: vmessAlterID,
            anyTLSPassword: anyTLSPassword,
            resolvedServerAddresses: addresses
        )
    }

    private static func isValidResolvedServerAddress(_ address: String) -> Bool {
        guard !address.isEmpty,
              address.count <= 253,
              !address.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }

        var ipv4 = in_addr()
        if address.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return true
        }

        var ipv6 = in6_addr()
        return address.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1
    }
}

public enum TunnelConfigManager {
    private static var appGroupURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupName
        )
    }

    private static var configURL: URL? {
        appGroupURL?.appendingPathComponent("tunnel_config.json", isDirectory: false)
    }

    public static func saveConfig(_ config: TunnelConfiguration) throws {
        let validated = try config.validated()
        guard let url = configURL else {
            throw TunnelConfigError.appGroupUnavailable
        }
        let data = try JSONEncoder().encode(validated)
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    public static func loadConfig() throws -> TunnelConfiguration {
        guard let url = configURL else {
            throw TunnelConfigError.appGroupUnavailable
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TunnelConfigError.missingConfiguration
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(TunnelConfiguration.self, from: data).validated()
        } catch let error as TunnelConfigError {
            throw error
        } catch {
            throw TunnelConfigError.corruptConfiguration
        }
    }
}

public enum TunnelConfigError: Error, LocalizedError, Equatable {
    case appGroupUnavailable
    case missingConfiguration
    case corruptConfiguration
    case unsupportedSchema
    case invalidNodeID
    case invalidServerAddress
    case invalidResolvedServerAddresses
    case invalidServerPort
    case invalidCredential
    case missingServerName
    case invalidWebSocketPath
    case tooManyHeaders
    case invalidHeader
    case invalidGRPCServiceName
    case invalidFlow
    case invalidReality
    case invalidTLSFingerprint
    case invalidTLSALPN
    case invalidTLSInsecure
    case invalidVMessSettings
    case invalidAnyTLSSettings

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "VPN storage isn't available. Please reinstall Aster and try again."
        case .missingConfiguration:
            return "A secure VPN location isn't available right now."
        case .corruptConfiguration, .unsupportedSchema:
            return "The VPN configuration needs to be refreshed."
        case .invalidNodeID, .invalidServerAddress, .invalidServerPort, .invalidCredential,
             .invalidResolvedServerAddresses,
             .missingServerName, .invalidWebSocketPath, .tooManyHeaders, .invalidHeader,
             .invalidGRPCServiceName, .invalidFlow, .invalidReality, .invalidTLSFingerprint,
             .invalidTLSALPN, .invalidTLSInsecure,
             .invalidVMessSettings, .invalidAnyTLSSettings:
            return "The selected VPN location is unavailable."
        }
    }
}
