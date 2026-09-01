import Foundation

struct UserProfile: Decodable, Equatable, Sendable {
    let id: String
    let email: String
    let username: String?
    let avatar: String?
    let emailVerified: Bool
    let isActive: Bool
    let isAdmin: Bool
    let isGuest: Bool
    let appStoreAccountAliases: [AppStoreAccountAliasProfile]

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case username
        case avatar
        case emailVerified
        case isActive
        case isAdmin
        case isGuest
        case appStoreAccountAliases
    }

    init(
        id: String,
        email: String,
        username: String?,
        avatar: String?,
        emailVerified: Bool,
        isActive: Bool,
        isAdmin: Bool,
        isGuest: Bool = false,
        appStoreAccountAliases: [AppStoreAccountAliasProfile] = []
    ) {
        self.id = id
        self.email = email
        self.username = username
        self.avatar = avatar
        self.emailVerified = emailVerified
        self.isActive = isActive
        self.isAdmin = isAdmin
        self.isGuest = isGuest
        self.appStoreAccountAliases = appStoreAccountAliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified) ?? false
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        isGuest = try container.decodeIfPresent(Bool.self, forKey: .isGuest) ?? false
        appStoreAccountAliases = try container.decodeIfPresent(
            [AppStoreAccountAliasProfile].self,
            forKey: .appStoreAccountAliases
        ) ?? []
    }
}

struct AppStoreAccountAliasProfile: Decodable, Equatable, Sendable {
    let appAccountToken: String
}

struct AccountDeletionResult: Decodable, Equatable, Sendable {
    let deletedAt: String
    let cancelledPendingOrders: Int
    let retainedData: [String]
    let appStoreSubscriptionAction: String
}
