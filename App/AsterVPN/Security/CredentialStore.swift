import Foundation
import Security

protocol CredentialStoring: Sendable {
    func load() async throws -> AuthTokens?
    func save(_ credentials: AuthTokens) async throws
    func clear() async throws
}

protocol InstallationIDStoring: Sendable {
    func loadOrCreate() async throws -> UUID
}

enum CredentialStoreError: LocalizedError {
    case encodingFailed
    case unexpectedData
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "无法安全保存登录信息"
        case .unexpectedData:
            return "本地登录信息已损坏"
        case let .keychain(status):
            if let description = SecCopyErrorMessageString(status, nil) as String? {
                return "钥匙串操作失败：\(description)"
            }
            return "钥匙串操作失败（\(status)）"
        }
    }
}

/// Stores both tokens as one Keychain item so a refresh-token rotation cannot
/// leave the app with a mismatched pair. Tokens are never written to UserDefaults.
actor KeychainCredentialStore: CredentialStoring {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.astervpn.Aster",
        account: String = "authenticated-session"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> AuthTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
        guard let data = result as? Data else {
            throw CredentialStoreError.unexpectedData
        }

        do {
            return try JSONDecoder().decode(AuthTokens.self, from: data)
        } catch {
            throw CredentialStoreError.unexpectedData
        }
    }

    func save(_ credentials: AuthTokens) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(credentials)
        } catch {
            throw CredentialStoreError.encodingFailed
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychain(updateStatus)
        }

        var newItem = baseQuery
        attributes.forEach { newItem[$0.key] = $0.value }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychain(addStatus)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// A non-secret, random installation identifier kept separately from session
/// credentials so signing out cannot reset a one-time guest trial.
actor KeychainInstallationIDStore: InstallationIDStoring {
    private let service: String
    private let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.astervpn.Aster",
        account: String = "installation-identifier"
    ) {
        self.service = service
        self.account = account
    }

    func loadOrCreate() throws -> UUID {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8),
           let identifier = UUID(uuidString: value) {
            return identifier
        }
        guard status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }

        let identifier = UUID()
        guard let data = identifier.uuidString.data(using: .utf8) else {
            throw CredentialStoreError.encodingFailed
        }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychain(addStatus)
        }
        return identifier
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Useful for previews and deterministic URLProtocol tests. Production code
/// defaults to `KeychainCredentialStore`.
actor InMemoryCredentialStore: CredentialStoring {
    private var credentials: AuthTokens?

    init(credentials: AuthTokens? = nil) {
        self.credentials = credentials
    }

    func load() -> AuthTokens? {
        credentials
    }

    func save(_ credentials: AuthTokens) {
        self.credentials = credentials
    }

    func clear() {
        credentials = nil
    }
}
