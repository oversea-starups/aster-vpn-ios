import Foundation

struct AppConfiguration {
    static let privacyPolicyURL: URL? = validatedPublicHTTPSURL(
        Bundle.main.object(forInfoDictionaryKey: "AsterPrivacyPolicyURL") as? String
    )

    static let nodeSubscriptionURL: URL? = validatedPublicHTTPSURL(
        Bundle.main.object(forInfoDictionaryKey: "AsterNodeSubscriptionURL") as? String
    )

    static let monthlyProductID = "com.aster.vpn.monthly"
    static let yearlyProductID = "com.aster.vpn.yearly"
    static let subscriptionProductIDs = [yearlyProductID, monthlyProductID]

    // Billing cadence is a StoreKit product concern; both current products
    // grant the same Pro capability tier. Additional tiers can be added here
    // only when a matching App Store product and entitlement are available.
    static let subscriptionTiersByProductID: [String: SubscriptionTier] = [
        monthlyProductID: .pro,
        yearlyProductID: .pro
    ]

    static func subscriptionTier(for productID: String) -> SubscriptionTier? {
        subscriptionTiersByProductID[productID]
    }

    static func validatedPublicHTTPSURL(_ value: String?) -> URL? {
        guard
            let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            !value.contains("$("),
            let components = URLComponents(string: value),
            components.scheme?.lowercased() == "https",
            components.user == nil,
            components.password == nil,
            components.fragment == nil,
            let host = components.host?.lowercased(),
            !host.isEmpty,
            !Self.isReservedHost(host),
            let url = components.url
        else {
            return nil
        }
        return url
    }

    private static func isReservedHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") ||
            host.hasSuffix(".internal") || host.hasSuffix(".invalid") || host.hasSuffix(".test") ||
            host == "example" || host.hasSuffix(".example") ||
            host == "example.com" || host.hasSuffix(".example.com") ||
            host == "example.net" || host.hasSuffix(".example.net") ||
            host == "example.org" || host.hasSuffix(".example.org") {
            return true
        }

        let ipv6 = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if ipv6 == "::" || ipv6 == "::1" || ipv6.hasPrefix("fc") || ipv6.hasPrefix("fd") ||
            ipv6.hasPrefix("fe8") || ipv6.hasPrefix("fe9") || ipv6.hasPrefix("fea") ||
            ipv6.hasPrefix("feb") || ipv6.hasPrefix("2001:db8") {
            return true
        }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }
        let a = octets[0]
        let b = octets[1]
        return a == 0 || a == 10 || a == 127 || a >= 224 ||
            (a == 100 && (64...127).contains(b)) ||
            (a == 169 && b == 254) ||
            (a == 172 && (16...31).contains(b)) ||
            (a == 192 && b == 168) ||
            (a == 192 && b == 0 && octets[2] == 2) ||
            (a == 198 && (b == 18 || b == 19 || b == 51)) ||
            (a == 203 && b == 0 && octets[2] == 113)
    }
}
