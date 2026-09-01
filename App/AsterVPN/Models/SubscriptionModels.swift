import Foundation

struct SubscriptionSummary: Decodable, Equatable, Sendable {
    let planName: String
    let status: String
    let totalTraffic: Int64
    let usedTraffic: Int64
    let remainingTraffic: Int64
    let expiredAt: String?
    let entitlementSources: [SubscriptionSourceSummary]
    let isGuest: Bool
    let trial: TrialSummary?

    private enum CodingKeys: String, CodingKey {
        case planName
        case status
        case totalTraffic
        case usedTraffic
        case remainingTraffic
        case expiredAt
        case entitlementSources
        case isGuest
        case trial
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planName = try container.decodeIfPresent(String.self, forKey: .planName)
            ?? "未激活"
        status = try container.decodeIfPresent(String.self, forKey: .status)
            ?? "inactive"
        totalTraffic = try Self.decodeByteCount(container, key: .totalTraffic)
        usedTraffic = try Self.decodeByteCount(container, key: .usedTraffic)
        remainingTraffic = try Self.decodeByteCount(container, key: .remainingTraffic)
        expiredAt = try container.decodeIfPresent(String.self, forKey: .expiredAt)
        entitlementSources = try container.decodeIfPresent(
            [SubscriptionSourceSummary].self,
            forKey: .entitlementSources
        ) ?? []
        isGuest = try container.decodeIfPresent(Bool.self, forKey: .isGuest) ?? false
        trial = try container.decodeIfPresent(TrialSummary.self, forKey: .trial)
    }

    private static func decodeByteCount(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Int64 {
        if let value = try? container.decode(Int64.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? container.decode(String.self, forKey: key),
           let number = Int64(value) {
            return number
        }
        return 0
    }
}

struct TrialSummary: Decodable, Equatable, Sendable {
    let status: String
    let startedAt: String?
    let expiresAt: String?
    let durationSeconds: Int
    let nodeLimit: Int
}

struct SubscriptionSourceSummary: Decodable, Equatable, Sendable {
    let source: String
    let planName: String
    let totalTraffic: Int64
    let usedTraffic: Int64
    let remainingTraffic: Int64
    let expiredAt: String?
}
