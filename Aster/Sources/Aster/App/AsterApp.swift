import SwiftUI

@main
struct AsterApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("privacy_disclosure_acknowledged_v1") private var acknowledgedPrivacyDisclosure = false

    init() {
#if ASTER_DEVICE_IMPORT
        DebugDeviceImportBootstrap.installIfPresent()
#endif
    }

    var body: some Scene {
        WindowGroup {
            AsterTabView()
                .sheet(
                    isPresented: Binding(
                        get: { !acknowledgedPrivacyDisclosure },
                        set: { isPresented in
                            if !isPresented {
                                acknowledgedPrivacyDisclosure = true
                            }
                        }
                    )
                ) {
                    VPNDataUseDisclosureView {
                        acknowledgedPrivacyDisclosure = true
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(true)
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active, acknowledgedPrivacyDisclosure {
                    Task {
                        await NodeCatalogStore.shared.refreshIfNeeded()
                    }
                }
            }
    }
}
