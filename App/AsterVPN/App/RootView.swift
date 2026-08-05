import SwiftUI

struct RootView: View {
    @EnvironmentObject private var vpnManager: VPNManager
    @ObservedObject var authSession: AuthSession
    @ObservedObject var nodeStore: NodeStore
    let purchaseCoordinator: StoreKitPurchaseCoordinator

    @AppStorage("accepted-data-disclosure-version")
    private var acceptedDataDisclosureVersion = 0
    @State private var showsDataDisclosure = false
    @State private var showsAuthentication = false
    @State private var authenticationRequestedWhileRestoring = false
    @State private var continuesToAuthenticationAfterDisclosure = false

    private static let currentDataDisclosureVersion = 2

    var body: some View {
        AppTabView(
            authSession: authSession,
            nodeStore: nodeStore,
            purchaseCoordinator: purchaseCoordinator,
            requestAuthentication: requestAuthentication
        )
        .sheet(
            isPresented: $showsDataDisclosure,
            onDismiss: continueAuthenticationAfterDisclosureIfNeeded
        ) {
            NavigationStack {
                PrivacyDisclosureView(
                    continueAction: {
                        acceptedDataDisclosureVersion = Self.currentDataDisclosureVersion
                        continuesToAuthenticationAfterDisclosure = true
                        showsDataDisclosure = false
                    },
                    cancelAction: {
                        continuesToAuthenticationAfterDisclosure = false
                        showsDataDisclosure = false
                    }
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAuthentication) {
            AuthenticationView(
                session: authSession,
                allowsDismissal: true
            )
            .interactiveDismissDisabled(authSession.isBusy)
        }
        .task {
            await vpnManager.reload()
            await authSession.restore()
        }
        .task(id: authSession.currentUser?.id) {
            guard authSession.phase == .signedIn,
                  let userID = authSession.currentUser?.id else {
                return
            }
            purchaseCoordinator.deactivate()
            nodeStore.activate(for: userID)
            await purchaseCoordinator.activate()
        }
        .onChange(of: authSession.phase) { phase in
            switch phase {
            case .restoring:
                break
            case .signedOut:
                purchaseCoordinator.deactivate()
                nodeStore.clearSession()
                if authenticationRequestedWhileRestoring {
                    authenticationRequestedWhileRestoring = false
                    requestAuthentication()
                }
            case .signedIn:
                authenticationRequestedWhileRestoring = false
                showsAuthentication = false
            }
        }
        .onChange(of: authSession.currentUser?.isGuest) { isGuest in
            if isGuest == false {
                showsAuthentication = false
            }
        }
    }

    private func requestAuthentication() {
        switch authSession.phase {
        case .restoring:
            authenticationRequestedWhileRestoring = true
        case .signedOut:
            authSession.clearMessages()
            if acceptedDataDisclosureVersion < Self.currentDataDisclosureVersion {
                continuesToAuthenticationAfterDisclosure = false
                showsDataDisclosure = true
            } else {
                showsAuthentication = true
            }
        case .signedIn:
            guard authSession.currentUser?.isGuest == true else { return }
            authSession.clearMessages()
            if acceptedDataDisclosureVersion < Self.currentDataDisclosureVersion {
                continuesToAuthenticationAfterDisclosure = false
                showsDataDisclosure = true
            } else {
                showsAuthentication = true
            }
        }
    }

    private func continueAuthenticationAfterDisclosureIfNeeded() {
        guard continuesToAuthenticationAfterDisclosure else { return }
        continuesToAuthenticationAfterDisclosure = false
        guard authSession.phase == .signedOut
                || authSession.currentUser?.isGuest == true else {
            return
        }
        showsAuthentication = true
    }
}

private struct AppTabView: View {
    @ObservedObject var authSession: AuthSession
    @ObservedObject var nodeStore: NodeStore
    let purchaseCoordinator: StoreKitPurchaseCoordinator
    let requestAuthentication: () -> Void

    var body: some View {
        TabView {
            NavigationStack {
                ConnectionView(
                    nodeStore: nodeStore,
                    authenticationPhase: authSession.phase,
                    requestAuthentication: requestAuthentication
                )
            }
            .tabItem {
                Label("连接", systemImage: "lock.shield")
            }

            NavigationStack {
                if authSession.phase == .signedIn {
                    PaywallView(
                        coordinator: purchaseCoordinator,
                        isGuest: authSession.currentUser?.isGuest == true,
                        requestAccountAssociation: requestAuthentication
                    )
                } else {
                    DeferredAuthenticationView(
                        navigationTitle: "订阅",
                        title: "登录后查看订阅",
                        detail: "你可以先浏览连接首页。购买、恢复订阅或同步已有权益时，再登录或注册并关联当前账号。",
                        systemImage: "sparkles",
                        isRestoring: authSession.phase == .restoring,
                        showsLegalLinks: false,
                        requestAuthentication: requestAuthentication
                    )
                }
            }
            .tabItem {
                Label("订阅", systemImage: "sparkles")
            }

            NavigationStack {
                if authSession.phase == .signedIn,
                   authSession.currentUser?.isGuest != true {
                    AccountView(session: authSession)
                } else if authSession.currentUser?.isGuest == true {
                    DeferredAuthenticationView(
                        navigationTitle: "账号",
                        title: "当前为游客模式",
                        detail: "试用和 App Store 订阅可以直接使用。关联邮箱账号后，可跨设备恢复权益并管理账号。",
                        systemImage: "person.crop.circle.badge.plus",
                        isRestoring: false,
                        showsLegalLinks: true,
                        requestAuthentication: requestAuthentication
                    )
                } else {
                    DeferredAuthenticationView(
                        navigationTitle: "账号",
                        title: "需要时再关联账号",
                        detail: "打开 App 无需先注册。连接、订阅或跨设备同步权益时，再登录或创建账号即可。",
                        systemImage: "person.crop.circle.badge.plus",
                        isRestoring: authSession.phase == .restoring,
                        showsLegalLinks: true,
                        requestAuthentication: requestAuthentication
                    )
                }
            }
            .tabItem {
                Label("账号", systemImage: "person.crop.circle")
            }
        }
    }
}

private struct DeferredAuthenticationView: View {
    let navigationTitle: String
    let title: String
    let detail: String
    let systemImage: String
    let isRestoring: Bool
    let showsLegalLinks: Bool
    let requestAuthentication: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: systemImage)
                    .font(.system(size: 52))
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.bold())
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: requestAuthentication) {
                    HStack {
                        if isRestoring {
                            ProgressView()
                        }
                        Text(isRestoring ? "正在恢复账号…" : "登录或注册")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRestoring)

                if showsLegalLinks {
                    VStack(spacing: 14) {
                        NavigationLink {
                            PrivacyDisclosureView(requiresAcknowledgement: false)
                        } label: {
                            Label("数据与隐私说明", systemImage: "hand.raised")
                        }

                        Link(
                            "完整隐私政策",
                            destination: AppConfiguration.current.privacyPolicyURL
                        )
                        Link(
                            "服务条款",
                            destination: AppConfiguration.current.termsOfServiceURL
                        )
                        Link(
                            "帮助与支持",
                            destination: AppConfiguration.current.supportURL
                        )
                    }
                    .font(.subheadline)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: 520)
            .padding(28)
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(navigationTitle)
    }
}
