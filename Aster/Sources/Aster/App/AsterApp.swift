import SwiftUI

@main
struct AsterApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
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
                        }
                    }
                }
        }
    }
}
