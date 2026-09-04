import Foundation

struct AppConfiguration: Equatable {
    let apiBaseURL: URL
    let publicSiteBaseURL: URL
    let privacyPolicyURL: URL
    let termsOfServiceURL: URL
    let supportURL: URL
    let packetTunnelBundleIdentifier: String
    let packetTunnelTransportAvailable: Bool
    let buildConfiguration: String

    static let current: AppConfiguration = {
        let environment = ProcessInfo.processInfo.environment
        let bundle = Bundle.main

        let apiValue = configuredValue(
            environmentKey: "ASTER_API_BASE_URL",
            infoKey: "AsterAPIBaseURL",
            environment: environment,
            bundle: bundle
        )
        let tunnelIdentifier = configuredValue(
            environmentKey: "ASTER_PACKET_TUNNEL_BUNDLE_ID",
            infoKey: "AsterPacketTunnelBundleIdentifier",
            environment: environment,
            bundle: bundle
        )
        let transportValue = configuredValue(
            environmentKey: "ASTER_PACKET_TUNNEL_TRANSPORT_AVAILABLE",
            infoKey: "AsterPacketTunnelTransportAvailable",
            environment: environment,
            bundle: bundle
        )
        let buildConfiguration = configuredValue(
            environmentKey: "ASTER_BUILD_CONFIGURATION",
            infoKey: "AsterBuildConfiguration",
            environment: environment,
            bundle: bundle
        )

        guard let apiURL = validatedHTTPURL(apiValue),
              !tunnelIdentifier.isEmpty else {
            preconditionFailure("ClashX VPN build configuration is incomplete")
        }

        let defaultSiteURL = originURL(for: apiURL)
        let siteURL = configuredURL(
            environmentKey: "ASTER_PUBLIC_SITE_BASE_URL",
            infoKey: "AsterPublicSiteBaseURL",
            environment: environment,
            bundle: bundle
        ) ?? defaultSiteURL
        let privacyURL = configuredURL(
            environmentKey: "ASTER_PRIVACY_POLICY_URL",
            infoKey: "AsterPrivacyPolicyURL",
            environment: environment,
            bundle: bundle
        ) ?? hashRouteURL(baseURL: siteURL, route: "/privacy")
        let termsURL = configuredURL(
            environmentKey: "ASTER_TERMS_OF_SERVICE_URL",
            infoKey: "AsterTermsOfServiceURL",
            environment: environment,
            bundle: bundle
        ) ?? hashRouteURL(baseURL: siteURL, route: "/terms")
        let supportURL = configuredURL(
            environmentKey: "ASTER_SUPPORT_URL",
            infoKey: "AsterSupportURL",
            environment: environment,
            bundle: bundle
        ) ?? siteURL

        let configuration = AppConfiguration(
            apiBaseURL: apiURL,
            publicSiteBaseURL: siteURL,
            privacyPolicyURL: privacyURL,
            termsOfServiceURL: termsURL,
            supportURL: supportURL,
            packetTunnelBundleIdentifier: tunnelIdentifier,
            packetTunnelTransportAvailable: [
                "1", "true", "yes",
            ].contains(transportValue.lowercased()),
            buildConfiguration: buildConfiguration
        )
        configuration.validateRelease()
        return configuration
    }()

    private func validateRelease() {
        guard buildConfiguration.caseInsensitiveCompare("Release") == .orderedSame else {
            return
        }

        let urls = [
            apiBaseURL,
            publicSiteBaseURL,
            privacyPolicyURL,
            termsOfServiceURL,
            supportURL,
        ]
        guard packetTunnelTransportAvailable,
              urls.allSatisfy(Self.isPublicReleaseURL) else {
            preconditionFailure(
                "Release configuration contains a placeholder, non-HTTPS URL, or disabled VPN transport"
            )
        }
    }

    private static func isPublicReleaseURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let rawHost = url.host?.lowercased() else {
            return false
        }

        let host = rawHost
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let blockedNames = [
            "localhost",
            "example",
            "invalid",
            "test",
            "local",
        ]
        guard !blockedNames.contains(host),
              !blockedNames.contains(where: { host.hasSuffix(".\($0)") }),
              host != "example.com",
              !host.hasSuffix(".example.com") else {
            return false
        }

        if host.contains(":") {
            return host != "::1"
                && !host.hasPrefix("fc")
                && !host.hasPrefix("fd")
                && !host.hasPrefix("fe8")
                && !host.hasPrefix("fe9")
                && !host.hasPrefix("fea")
                && !host.hasPrefix("feb")
        }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4,
              octets.allSatisfy({ (0...255).contains($0) }) else {
            return true
        }

        let first = octets[0]
        let second = octets[1]
        return first != 0
            && first != 10
            && first != 127
            && !(first == 100 && (64...127).contains(second))
            && !(first == 169 && second == 254)
            && !(first == 172 && (16...31).contains(second))
            && !(first == 192 && second == 168)
            && first < 224
    }

    private static func configuredValue(
        environmentKey: String,
        infoKey: String,
        environment: [String: String],
        bundle: Bundle
    ) -> String {
        let value = environment[environmentKey]
            ?? bundle.object(forInfoDictionaryKey: infoKey) as? String
            ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func configuredURL(
        environmentKey: String,
        infoKey: String,
        environment: [String: String],
        bundle: Bundle
    ) -> URL? {
        validatedHTTPURL(
            configuredValue(
                environmentKey: environmentKey,
                infoKey: infoKey,
                environment: environment,
                bundle: bundle
            )
        )
    }

    private static func validatedHTTPURL(_ value: String) -> URL? {
        guard !value.isEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    private static func originURL(for url: URL) -> URL {
        var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )!
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    private static func hashRouteURL(baseURL: URL, route: String) -> URL {
        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )!
        components.path = "/"
        components.query = nil
        components.fragment = route
        return components.url!
    }
}
