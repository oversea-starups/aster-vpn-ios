import Foundation

/// Capability tier, kept separate from billing cadence so new VIP packages can
/// be introduced without changing connection or rewarded-time logic.
///
/// Only tiers mapped to a verified StoreKit product are surfaced to users.
/// `plus` is reserved for a future product; it is intentionally not advertised
/// or granted by the current catalog.
enum SubscriptionTier: Int, Comparable, Sendable {
    case free = 0
    case plus = 1
    case pro = 2

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .free: return "Free plan"
        case .plus: return "Aster Plus"
        case .pro: return "Aster Pro"
        }
    }

    /// The current app only has one entitlement capability. A future Plus
    /// product may be paid without necessarily receiving Pro's unlimited
    /// protection, so callers should use the capability-specific property.
    var hasUnlimitedProtection: Bool { self == .pro }
}
