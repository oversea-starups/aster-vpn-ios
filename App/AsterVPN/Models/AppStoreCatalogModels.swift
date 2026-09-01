import Foundation

/// A product the backend has explicitly enabled and mapped to an internal plan.
///
/// The backend catalog is the allowlist. A StoreKit product that is not present
/// in this response must never be offered by the app.
struct AppStoreCatalogItem: Decodable, Equatable, Identifiable, Sendable {
    let productId: String
    let plan: AppStorePlanDetails

    var id: String { productId }
}

struct AppStorePlanDetails: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let description: String?
    let period: String
    let traffic: Int
    let speed: Int
    let deviceLimit: Int
    let regionCount: Int
    let features: AppStorePlanFeatures
}

/// Prisma's JSON field has historically contained either a JSON array or a
/// JSON-encoded string. Decode both forms so a legacy plan cannot break the
/// whole StoreKit catalog.
struct AppStorePlanFeatures: Decodable, Equatable, Sendable {
    let values: [String]

    init(values: [String]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let values = try? container.decode([String].self) {
            self.values = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return
        }

        if let encodedValue = try? container.decode(String.self) {
            let trimmedValue = encodedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = trimmedValue.data(using: .utf8),
               let decodedValues = try? JSONDecoder().decode([String].self, from: data) {
                self.values = decodedValues.filter {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            } else if trimmedValue.isEmpty {
                self.values = []
            } else {
                self.values = [trimmedValue]
            }
            return
        }

        // Unknown JSON written by an old admin client should not make every
        // valid StoreKit product disappear from the paywall.
        self.values = []
    }
}
