import SwiftUI

@main
struct AsterApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AsterAnalytics.configure()
        let firstOpen = !UserDefaults.standard.bool(forKey: "analytics.has_opened")
        AsterAnalytics.log(
            AsterAnalytics.Event.appOpen,
            parameters: [
                "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                "first_open": firstOpen
            ]
        )
        UserDefaults.standard.set(true, forKey: "analytics.has_opened")
#if ASTER_DEVICE_IMPORT
        DebugDeviceImportBootstrap.installIfPresent()
#endif
    }

    var body: some Scene {
        WindowGroup {
            AsterTabView()
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        Task {
                            await NodeCatalogStore.shared.refreshIfNeeded()
                            await SubscriptionStore.shared.reloadProductsIfNeeded()
                        }
                    }
                }
        }
    }
}
