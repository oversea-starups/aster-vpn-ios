import Foundation

struct VPNNode: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let region: String
    let host: String
    let port: Int
    let protocolName: String
    let method: String?
    let password: String?
    let uuid: String?
    let alterId: Int?
    let tls: Bool
    let network: String
    let webSocketPath: String?
    let grpcServiceName: String?
    let protocolConfiguration: JSONValue?
    let tags: [String]
    let rate: Double

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case region
        case host
        case port
        case protocolName = "protocol"
        case method
        case password
        case uuid
        case alterId
        case tls
        case network
        case webSocketPath = "wsPath"
        case grpcServiceName
        case protocolConfiguration = "protocolConfig"
        case tags
        case rate
    }

    init(
        id: String,
        name: String,
        region: String,
        host: String,
        port: Int,
        protocolName: String,
        method: String? = nil,
        password: String? = nil,
        uuid: String? = nil,
        alterId: Int? = nil,
        tls: Bool = false,
        network: String = "tcp",
        webSocketPath: String? = nil,
        grpcServiceName: String? = nil,
        protocolConfiguration: JSONValue? = nil,
        tags: [String] = [],
        rate: Double = 1
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.host = host
        self.port = port
        self.protocolName = protocolName
        self.method = method
        self.password = password
        self.uuid = uuid
        self.alterId = alterId
        self.tls = tls
        self.network = network
        self.webSocketPath = webSocketPath
        self.grpcServiceName = grpcServiceName
        self.protocolConfiguration = protocolConfiguration
        self.tags = tags
        self.rate = rate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        region = try container.decode(String.self, forKey: .region)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        protocolName = try container.decode(String.self, forKey: .protocolName)
        method = try container.decodeIfPresent(String.self, forKey: .method)
        password = try container.decodeIfPresent(String.self, forKey: .password)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        alterId = try container.decodeIfPresent(Int.self, forKey: .alterId)
        tls = try container.decodeIfPresent(Bool.self, forKey: .tls) ?? false
        network = try container.decodeIfPresent(String.self, forKey: .network) ?? "tcp"
        webSocketPath = try container.decodeIfPresent(String.self, forKey: .webSocketPath)
        grpcServiceName = try container.decodeIfPresent(String.self, forKey: .grpcServiceName)
        protocolConfiguration = try container.decodeIfPresent(
            JSONValue.self,
            forKey: .protocolConfiguration
        )
        tags = try Self.decodeTags(from: container)
        rate = try Self.decodeRate(from: container)
    }

    var normalizedProtocol: String {
        protocolName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var serverAddress: String {
        "\(host):\(port)"
    }

    var configurationIssue: String? {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...65_535).contains(port) else {
            return "节点地址或端口无效"
        }

        switch normalizedProtocol {
        case "vmess", "vless":
            guard uuid?.isEmpty == false else {
                return "\(normalizedProtocol.uppercased()) 节点缺少 UUID"
            }
        case "anytls":
            guard password?.isEmpty == false else {
                return "AnyTLS 节点缺少密码"
            }
        default:
            return "暂不支持 \(protocolName) 协议"
        }

        return nil
    }

    private static func decodeRate(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Double {
        if let number = try? container.decode(Double.self, forKey: .rate) {
            return number
        }
        if let string = try? container.decode(String.self, forKey: .rate),
           let number = Double(string) {
            return number
        }
        return 1
    }

    private static func decodeTags(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [String] {
        if let values = try? container.decode([String].self, forKey: .tags) {
            return values
        }
        guard let value = try? container.decode(String.self, forKey: .tags),
              !value.isEmpty else {
            return []
        }
        if let data = value.data(using: .utf8),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            return values
        }
        return [value]
    }
}

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
