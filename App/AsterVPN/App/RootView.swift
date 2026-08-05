import SwiftUI

struct RootView: View {
    @EnvironmentObject private var vpnManager: VPNManager
    @ObservedObject var authSession: AuthSession
    @ObservedObject var nodeStore: NodeStore
    let purchaseCoordinator: StoreKitPurchaseCoordinator

    @AppStorage("accepted-data-disclosure-version")
    private var acceptedDataDisclosureVersion = 0

    private static let currentDataDisclosureVersion = 1

    var body: some View {
        Group {
            if acceptedDataDisclosureVersion < Self.currentDataDisclosureVersion {
                NavigationStack {
                    PrivacyDisclosureView {
                        acceptedDataDisclosureVersion = Self.currentDataDisclosureVersion
                    }
                }
            } else {
                switch authSession.phase {
                case .restoring:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("正在恢复安全登录状态…")
                            .foregroundStyle(.secondary)
                    }
                case .signedOut:
                    AuthenticationView(session: authSession)
                case .signedIn:
                    AuthenticatedTabView(
                        authSession: authSession,
                        nodeStore: nodeStore,
                        purchaseCoordinator: purchaseCoordinator
                    )
                }
            }
        }
        .task(id: acceptedDataDisclosureVersion) {
            guard acceptedDataDisclosureVersion >= Self.currentDataDisclosureVersion else {
                return
            }
            await vpnManager.reload()
            await authSession.restore()
        }
        .task(id: authSession.currentUser?.id) {
            guard authSession.phase == .signedIn,
                  let userID = authSession.currentUser?.id else {
                return
            }
            nodeStore.activate(for: userID)
            await purchaseCoordinator.activate()
        }
        .onChange(of: authSession.phase) { phase in
            guard phase == .signedOut else { return }
            purchaseCoordinator.deactivate()
            nodeStore.clearSession()
        }
    }
}

private struct AuthenticatedTabView: View {
    @ObservedObject var authSession: AuthSession
    @ObservedObject var nodeStore: NodeStore
    let purchaseCoordinator: StoreKitPurchaseCoordinator

    var body: some View {
        TabView {
            NavigationStack {
                ConnectionView(nodeStore: nodeStore)
            }
            .tabItem {
                Label("连接", systemImage: "lock.shield")
            }

            NavigationStack {
                PaywallView(coordinator: purchaseCoordinator)
            }
            .tabItem {
                Label("订阅", systemImage: "sparkles")
            }

            NavigationStack {
                AccountView(session: authSession)
            }
            .tabItem {
                Label("账号", systemImage: "person.crop.circle")
            }
        }
    }
}
