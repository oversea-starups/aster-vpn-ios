import Foundation

/// Server-authoritative access snapshot returned by
/// `GET /api/storekit/entitlement`.
struct AppStoreEntitlementSnapshot: Decodable, Equatable, Sendable {
    let appAccountToken: UUID
    let subscription: EffectiveSubscriptionSnapshot?
    let appStoreTransaction: AppStoreTransactionSnapshot?

    /// Local StoreKit state is deliberately not consulted here. The backend
    /// combines web and App Store quota pools and remains the authorization
    /// source of truth.
    var grantsAccess: Bool {
        subscription?.status == "active"
    }
}

struct EffectiveSubscriptionSnapshot: Decodable, Equatable, Sendable {
    let planName: String?
    let status: String
    let totalTraffic: String
    let usedTraffic: String
    let remainingTraffic: String
    let expiredAt: String?
    let sources: [EntitlementSourceSnapshot]
}

struct EntitlementSourceSnapshot: Decodable, Equatable, Identifiable, Sendable {
    let source: String
    let planName: String
    let totalTraffic: String
    let usedTraffic: String
    let remainingTraffic: String
    let expiredAt: String?

    var id: String {
        [source, planName, expiredAt ?? "never"].joined(separator: ":")
    }
}

struct AppStoreTransactionSnapshot: Decodable, Equatable, Sendable {
    let productId: String
    let status: String
    let environment: String
    let effectiveExpiresAt: String
    let totalTraffic: String
    let usedTraffic: String
}

/// Result returned after the backend has verified and persisted an Apple JWS.
struct AppStoreTransactionSyncResult: Decodable, Equatable, Sendable {
    let transactionId: String
    let originalTransactionId: String
    let productId: String
    let environment: String
    let status: String
    let accountInactive: Bool
    let stale: Bool
    let effectiveExpiresAt: String
}
