import Foundation

#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif

enum AsterAnalytics {
    enum Event {
        static let appOpen = "app_open"
        static let connectTap = "connect_tap"
        static let connectSuccess = "connect_success"
        static let connectFail = "connect_fail"
        static let demoStart = "demo_start"
        static let demoEnd = "demo_end"
        static let paywallView = "paywall_view"
        static let purchaseStart = "purchase_start"
        static let purchaseSuccess = "purchase_success"
        static let restoreSuccess = "restore_success"
    }

    static func configure() {
#if canImport(FirebaseCore)
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil,
              FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
#endif
    }

    static func log(_ name: String, parameters: [String: Any] = [:]) {
#if canImport(FirebaseAnalytics)
        Analytics.logEvent(name, parameters: parameters.isEmpty ? nil : parameters)
#else
        _ = name
        _ = parameters
#endif
    }
}
