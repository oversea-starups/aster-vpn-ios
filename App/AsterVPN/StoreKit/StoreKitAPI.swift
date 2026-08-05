import Foundation

struct StoreKitAccountContext: Equatable, Sendable {
    let userID: UUID
    let sessionGeneration: UUID

    init(userID: UUID, sessionGeneration: UUID) {
        self.userID = userID
        self.sessionGeneration = sessionGeneration
    }
}

/// The authentication feature implements this boundary. Keeping it as a
/// protocol lets StoreKit consume the current user UUID without owning
/// authentication state, token storage, or refresh policy.
@MainActor
protocol StoreKitAccountProviding {
    func currentStoreKitAccount() async throws -> StoreKitAccountContext
}

protocol StoreKitAPIProviding {
    func fetchAllowedProducts() async throws -> [AppStoreCatalogItem]
    func fetchEntitlement() async throws -> AppStoreEntitlementSnapshot
    func syncTransaction(jwsRepresentation: String) async throws -> AppStoreTransactionSyncResult
}

enum AsterStorePurchaseError: Error, LocalizedError {
    case authenticationRequired
    case noProductsConfigured
    case backendAccountMismatch
    case transactionAccountMismatch
    case unverifiedTransaction
    case inactiveAccount
    case unavailableWindowScene
    case restoreIncomplete(successful: Int)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "请先登录后再购买订阅。"
        case .noProductsConfigured:
            return "当前没有可购买的 App Store 订阅，请稍后再试。"
        case .backendAccountMismatch:
            return "服务器订阅信息与当前账号不一致，请重新登录。"
        case .transactionAccountMismatch:
            return "该 App Store 订阅已绑定到另一个 Aster VPN 账号。"
        case .unverifiedTransaction:
            return "无法验证 App Store 交易，未同步订阅权益。"
        case .inactiveAccount:
            return "当前账号已停用，无法激活订阅。"
        case .unavailableWindowScene:
            return "暂时无法打开 Apple 订阅管理页面。"
        case let .restoreIncomplete(successful):
            if successful > 0 {
                return "已恢复 \(successful) 笔订阅，但仍有交易未能同步，请稍后重试。"
            }
            return "没有可恢复的订阅，或订阅属于其他 Aster VPN 账号。"
        }
    }
}

/// Adapter over the app's shared authenticated client. APIClient owns Keychain
/// credentials and refresh serialization; StoreKit never reads or stores JWTs.
struct StoreKitAPIClient: StoreKitAPIProviding {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchAllowedProducts() async throws -> [AppStoreCatalogItem] {
        try await client.send(
            .get,
            path: "storekit/products",
            requiresAuthorization: false,
            as: [AppStoreCatalogItem].self
        )
    }

    func fetchEntitlement() async throws -> AppStoreEntitlementSnapshot {
        try await client.send(
            .get,
            path: "storekit/entitlement",
            as: AppStoreEntitlementSnapshot.self
        )
    }

    func syncTransaction(jwsRepresentation: String) async throws -> AppStoreTransactionSyncResult {
        try await client.send(
            .post,
            path: "storekit/transactions/sync",
            body: SyncTransactionRequest(signedTransactionInfo: jwsRepresentation),
            as: AppStoreTransactionSyncResult.self
        )
    }
}

private struct SyncTransactionRequest: Encodable, Sendable {
    let signedTransactionInfo: String
}

extension AuthSession: StoreKitAccountProviding {
    func currentStoreKitAccount() async throws -> StoreKitAccountContext {
        guard phase == .signedIn,
              let userIDValue = currentUser?.id,
              let userID = UUID(uuidString: userIDValue) else {
            throw AsterStorePurchaseError.authenticationRequired
        }
        return StoreKitAccountContext(
            userID: userID,
            sessionGeneration: sessionGeneration
        )
    }
}
