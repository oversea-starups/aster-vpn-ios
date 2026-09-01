import Foundation
import Security

struct TunnelCredentialRecord: Codable, Equatable, Sendable {
    let ownerUserIdentifier: String
    let nodeIdentifier: String
    let serverAddress: String
    let nodeData: Data
}

protocol TunnelCredentialStoring {
    func save(
        _ record: TunnelCredentialRecord,
        reference: String
    ) throws
    func load(reference: String) throws -> TunnelCredentialRecord
    func delete(reference: String) throws
    func deleteAll() throws
}

struct KeychainTunnelCredentialStore: TunnelCredentialStoring {
    private static let service = "com.astervpn.Aster.tunnel-node"

    private let accessGroup: String?

    init(bundle: Bundle = .main) {
        let configuredGroup = bundle.object(
            forInfoDictionaryKey: "AsterKeychainAccessGroup"
        ) as? String
        if let configuredGroup,
           !configuredGroup.isEmpty,
           !configuredGroup.contains("$(") {
            accessGroup = configuredGroup
        } else {
            accessGroup = nil
        }
    }

    func save(
        _ record: TunnelCredentialRecord,
        reference: String
    ) throws {
        let value = try JSONEncoder().encode(record)
        let query = try itemQuery(reference: reference)
        let updates: [CFString: Any] = [
            kSecValueData: value,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            updates as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw TunnelCredentialStoreError.keychain(updateStatus)
        }

        var item = query
        updates.forEach { item[$0] = $1 }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw TunnelCredentialStoreError.keychain(addStatus)
        }
    }

    func load(reference: String) throws -> TunnelCredentialRecord {
        var query = try itemQuery(reference: reference)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                throw TunnelCredentialStoreError.notFound
            }
            throw TunnelCredentialStoreError.keychain(status)
        }

        do {
            return try JSONDecoder().decode(
                TunnelCredentialRecord.self,
                from: data
            )
        } catch {
            throw TunnelCredentialStoreError.invalidRecord
        }
    }

    func delete(reference: String) throws {
        let status = SecItemDelete(
            try itemQuery(reference: reference) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TunnelCredentialStoreError.keychain(status)
        }
    }

    func deleteAll() throws {
        let status = SecItemDelete(try serviceQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TunnelCredentialStoreError.keychain(status)
        }
    }

    private func itemQuery(reference: String) throws -> [CFString: Any] {
        guard !reference.isEmpty else {
            throw TunnelCredentialStoreError.invalidReference
        }
        var query = try serviceQuery()
        query[kSecAttrAccount] = reference
        return query
    }

    private func serviceQuery() throws -> [CFString: Any] {
        guard let accessGroup else {
            throw TunnelCredentialStoreError.missingAccessGroup
        }
        return [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccessGroup: accessGroup,
        ]
    }
}

enum TunnelCredentialStoreError: LocalizedError {
    case missingAccessGroup
    case invalidReference
    case notFound
    case invalidRecord
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingAccessGroup:
            return "VPN credential access group is not configured."
        case .invalidReference:
            return "VPN credential reference is invalid."
        case .notFound:
            return "VPN credentials are no longer available."
        case .invalidRecord:
            return "VPN credentials are invalid."
        case let .keychain(status):
            return "VPN credential storage failed (\(status))."
        }
    }
}
