import Foundation

@MainActor
final class NodeStore: ObservableObject {
    @Published private(set) var nodes: [VPNNode] = []
    @Published private(set) var subscription: SubscriptionSummary?
    @Published private(set) var selectedNodeID: String?
    @Published private(set) var sessionOwnerID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let client: APIClient
    private let vpnManager: VPNManager
    private let defaults: UserDefaults
    private let selectedNodeKey: String
    private let authenticationFailureHandler: (Error) -> Void
    private var sessionGeneration = UUID()
    private var pendingForcedReload = false

    init(
        client: APIClient,
        vpnManager: VPNManager,
        defaults: UserDefaults = .standard,
        selectedNodeKey: String = "selected-vpn-node-id",
        authenticationFailureHandler: @escaping (Error) -> Void = { _ in }
    ) {
        self.client = client
        self.vpnManager = vpnManager
        self.defaults = defaults
        self.selectedNodeKey = selectedNodeKey
        self.authenticationFailureHandler = authenticationFailureHandler
    }

    var selectedNode: VPNNode? {
        if let selectedNodeID,
           let selected = nodes.first(where: { $0.id == selectedNodeID }) {
            return selected
        }
        return nodes.first(where: { $0.configurationIssue == nil })
    }

    var hasUsableNode: Bool {
        selectedNode?.configurationIssue == nil
    }

    var canStartTrial: Bool {
        subscription?.trial?.status == "trial_pending"
            && subscription?.entitlementSources.contains(
                where: { $0.source == "app_store" }
            ) != true
    }

    func activate(for userID: String) {
        let normalizedUserID = userID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedUserID.isEmpty, sessionOwnerID != normalizedUserID else {
            return
        }

        sessionGeneration = UUID()
        sessionOwnerID = normalizedUserID
        vpnManager.authorizeConnections(
            for: normalizedUserID,
            generation: sessionGeneration
        )
        nodes = []
        subscription = nil
        selectedNodeID = defaults.string(
            forKey: selectionKey(for: normalizedUserID)
        )
        pendingForcedReload = false
        isLoading = false
        errorMessage = nil
    }

    func load(force: Bool = false) async {
        guard sessionOwnerID != nil else {
            errorMessage = "账号信息尚未恢复，请稍后重试。"
            return
        }
        if isLoading {
            if force {
                pendingForcedReload = true
            }
            return
        }
        guard force || nodes.isEmpty || subscription == nil else {
            return
        }

        let generation = sessionGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if sessionGeneration == generation {
                isLoading = false
                if pendingForcedReload {
                    pendingForcedReload = false
                    Task { [weak self] in
                        guard let self,
                              self.sessionGeneration == generation else {
                            return
                        }
                        await self.load(force: true)
                    }
                }
            }
        }

        async let subscriptionRequest = fetchSubscription()
        async let nodeRequest = fetchNodes()
        let (subscriptionResult, nodeResult) = await (
            subscriptionRequest,
            nodeRequest
        )
        guard sessionGeneration == generation else {
            return
        }

        var failures: [Error] = []
        switch subscriptionResult {
        case let .success(subscription):
            self.subscription = subscription
        case let .failure(error):
            subscription = nil
            failures.append(error)
        }

        switch nodeResult {
        case let .success(nodes):
            self.nodes = nodes
            if selectedNode == nil,
               let fallback = nodes.first(
                where: { $0.configurationIssue == nil }
               ) {
                select(fallback.id)
            }
        case let .failure(error):
            nodes = []
            failures.append(error)
        }

        if let authenticationError = failures.first(
            where: {
                ($0 as? APIClientError)?.isAuthenticationFailure == true
            }
        ) {
            pendingForcedReload = false
            authenticationFailureHandler(authenticationError)
        } else if canStartTrial {
            // Pending trials intentionally receive no node credentials. The
            // first connection atomically starts the clock before fetching
            // the two trial nodes.
            errorMessage = nil
        } else if let firstFailure = failures.first {
            present(firstFailure)
        }
    }

    func select(_ nodeID: String) {
        guard let sessionOwnerID,
              nodes.contains(where: { $0.id == nodeID }) else {
            return
        }
        selectedNodeID = nodeID
        defaults.set(nodeID, forKey: selectionKey(for: sessionOwnerID))
        errorMessage = nil
    }

    func toggleConnection() async {
        if vpnManager.status == .connected
            || vpnManager.status == .connecting
            || vpnManager.status == .reasserting {
            await vpnManager.disconnect()
            return
        }

        guard AppConfiguration.current.packetTunnelTransportAvailable else {
            errorMessage = "此构建尚未链接经过审核的 VPN 传输内核，因此不会接管设备流量。"
            return
        }

        guard let sessionOwnerID else {
            errorMessage = "当前登录会话尚未就绪，请重新登录。"
            return
        }
        guard !isLoading else {
            errorMessage = "正在刷新订阅和节点，请稍后重试。"
            return
        }
        let generation = sessionGeneration

        // Revalidate entitlement and fetch a current node credential before
        // every new connection attempt. A node cached while a subscription was
        // active must not remain connectable after access expires.
        await load(force: true)
        guard self.sessionGeneration == generation,
              self.sessionOwnerID == sessionOwnerID else {
            return
        }

        if canStartTrial {
            do {
                subscription = try await startTrial()
            } catch {
                present(error)
                return
            }
            await load(force: true)
            guard self.sessionGeneration == generation,
                  self.sessionOwnerID == sessionOwnerID else {
                return
            }
        }

        guard let selectedNode else {
            errorMessage = "当前没有可用节点，请刷新或先开通订阅。"
            return
        }
        if let issue = selectedNode.configurationIssue {
            errorMessage = issue
            return
        }

        do {
            try await vpnManager.install(
                configuration: TunnelConfiguration(
                    node: selectedNode,
                    ownerUserIdentifier: sessionOwnerID,
                    credentialReference: UUID().uuidString,
                    accessExpiresAt: subscription.flatMap(accessExpiration)
                ),
                expectedAuthorizationGeneration: generation
            )
            guard self.sessionGeneration == generation,
                  self.sessionOwnerID == sessionOwnerID else {
                return
            }
            await vpnManager.toggleConnection(
                expectedOwnerUserIdentifier: sessionOwnerID,
                expectedAuthorizationGeneration: generation
            )
            errorMessage = vpnManager.errorMessage
        } catch {
            present(error)
        }
    }

    func clearSession() {
        sessionGeneration = UUID()
        vpnManager.revokeConnections()
        sessionOwnerID = nil
        nodes = []
        subscription = nil
        selectedNodeID = nil
        pendingForcedReload = false
        isLoading = false
        errorMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private func present(_ error: Error) {
        if error is CancellationError {
            return
        }
        errorMessage = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    private func fetchSubscription() async -> Result<SubscriptionSummary, Error> {
        do {
            return .success(
                try await client.send(
                    .get,
                    path: "subscribe",
                    as: SubscriptionSummary.self
                )
            )
        } catch {
            return .failure(error)
        }
    }

    private func fetchNodes() async -> Result<[VPNNode], Error> {
        do {
            return .success(
                try await client.send(
                    .get,
                    path: "subscribe/nodes",
                    as: [VPNNode].self
                )
            )
        } catch {
            return .failure(error)
        }
    }

    private func startTrial() async throws -> SubscriptionSummary {
        try await client.send(
            .post,
            path: "subscribe/trial/start",
            as: SubscriptionSummary.self
        )
    }

    private func accessExpiration(_ subscription: SubscriptionSummary) -> Date? {
        guard let value = subscription.expiredAt else { return nil }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter.date(from: value)
    }

    private func selectionKey(for userID: String) -> String {
        "\(selectedNodeKey).\(userID)"
    }
}
