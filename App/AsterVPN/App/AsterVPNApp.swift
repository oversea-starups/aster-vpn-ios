import SwiftUI

@main
struct AsterVPNApp: App {
    @StateObject private var vpnManager: VPNManager
    @StateObject private var authSession: AuthSession
    @StateObject private var nodeStore: NodeStore
    @StateObject private var purchaseCoordinator: StoreKitPurchaseCoordinator

    @MainActor
    init() {
        let client = APIClient(baseURL: AppConfiguration.current.apiBaseURL)
        let vpnManager = VPNManager()
        let authSession = AuthSession(
            client: client,
            sessionInvalidationHandler: {
                vpnManager.revokeConnections()
            },
            sessionTerminationHandler: {
                try await vpnManager.removeConfiguration()
            }
        )

        _vpnManager = StateObject(wrappedValue: vpnManager)
        _authSession = StateObject(wrappedValue: authSession)
        let nodeStore = NodeStore(
            client: client,
            vpnManager: vpnManager,
            authenticationFailureHandler: { [weak authSession] error in
                authSession?.handleProtectedRequestError(error)
            }
        )
        _nodeStore = StateObject(wrappedValue: nodeStore)
        _purchaseCoordinator = StateObject(
            wrappedValue: StoreKitPurchaseCoordinator(
                api: StoreKitAPIClient(client: client),
                accountProvider: authSession,
                authenticationFailureHandler: { [weak authSession] error in
                    authSession?.handleProtectedRequestError(error)
                },
                entitlementChangedHandler: { [weak nodeStore] in
                    await nodeStore?.load(force: true)
                }
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                authSession: authSession,
                nodeStore: nodeStore,
                purchaseCoordinator: purchaseCoordinator
            )
                .environmentObject(vpnManager)
        }
    }
}
