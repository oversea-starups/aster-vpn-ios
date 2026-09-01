import Foundation

public struct TunnelProviderRequest: Codable, Equatable {
    public enum Command: String, Codable {
        case readiness = "readiness.v1"
    }

    public let schemaVersion: Int
    public let command: Command

    public init(schemaVersion: Int = 1, command: Command) {
        self.schemaVersion = schemaVersion
        self.command = command
    }
}

public struct TunnelProviderStatus: Codable, Equatable {
    public let schemaVersion: Int
    public let dataPlaneReady: Bool

    public init(schemaVersion: Int = 1, dataPlaneReady: Bool) {
        self.schemaVersion = schemaVersion
        self.dataPlaneReady = dataPlaneReady
    }
}

public enum TunnelProviderMessageCodec {
    public static func makeReadinessRequest() throws -> Data {
        try JSONEncoder().encode(
            TunnelProviderRequest(command: .readiness)
        )
    }

    public static func decodeRequest(_ data: Data) throws -> TunnelProviderRequest {
        let request = try JSONDecoder().decode(TunnelProviderRequest.self, from: data)
        guard request.schemaVersion == 1 else {
            throw TunnelProviderMessageError.unsupportedSchema
        }
        return request
    }

    public static func makeStatus(dataPlaneReady: Bool) throws -> Data {
        try JSONEncoder().encode(
            TunnelProviderStatus(dataPlaneReady: dataPlaneReady)
        )
    }

    public static func decodeStatus(_ data: Data) throws -> TunnelProviderStatus {
        let status = try JSONDecoder().decode(TunnelProviderStatus.self, from: data)
        guard status.schemaVersion == 1 else {
            throw TunnelProviderMessageError.unsupportedSchema
        }
        return status
    }
}

public enum TunnelProviderMessageError: Error, Equatable {
    case unsupportedSchema
}
