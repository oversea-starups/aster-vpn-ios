import Foundation
import NetworkExtension

@MainActor
final class VPNManager: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private let notificationCenter: NotificationCenter
    private let credentialStore: any TunnelCredentialStoring
    private var authorizedOwnerUserIdentifier: String?
    private var authorizationGeneration = UUID()
    private var operationLocked = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingOperationCount = 0

    init(
        notificationCenter: NotificationCenter = .default,
        credentialStore: any TunnelCredentialStoring = KeychainTunnelCredentialStore()
    ) {
        self.notificationCenter = notificationCenter
        self.credentialStore = credentialStore
        statusObserver = notificationCenter.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      let connection = notification.object as? NEVPNConnection,
                      connection === self.manager?.connection else {
                    return
                }
                self.status = connection.status
            }
        }
    }

    deinit {
        if let statusObserver {
            notificationCenter.removeObserver(statusObserver)
        }
    }

    var actionTitle: String {
        switch status {
        case .connected, .connecting, .reasserting:
            return "断开连接"
        default:
            return "连接"
        }
    }

    var statusDescription: String {
        switch status {
        case .invalid: return "尚未配置"
        case .disconnected: return "未连接"
        case .connecting: return "正在连接"
        case .connected: return "已保护"
        case .reasserting: return "正在恢复连接"
        case .disconnecting: return "正在断开"
        @unknown default: return "状态未知"
        }
    }

    var isConfigured: Bool {
        manager != nil
    }

    var configuredServerAddress: String? {
        (manager?.protocolConfiguration as? NETunnelProviderProtocol)?.serverAddress
    }

    var configuredNodeIdentifier: String? {
        guard let tunnelProtocol = manager?.protocolConfiguration
                as? NETunnelProviderProtocol else {
            return nil
        }
        return tunnelProtocol.providerConfiguration?["nodeIdentifier"] as? String
    }

    var configuredOwnerUserIdentifier: String? {
        guard let tunnelProtocol = manager?.protocolConfiguration
                as? NETunnelProviderProtocol else {
            return nil
        }
        return tunnelProtocol.providerConfiguration?["ownerUserIdentifier"] as? String
    }

    var configuredCredentialReference: String? {
        guard let tunnelProtocol = manager?.protocolConfiguration
                as? NETunnelProviderProtocol else {
            return nil
        }
        return tunnelProtocol.providerConfiguration?[
            "credentialReference"
        ] as? String
    }

    func authorizeConnections(
        for ownerUserIdentifier: String,
        generation: UUID
    ) {
        authorizedOwnerUserIdentifier = ownerUserIdentifier
        authorizationGeneration = generation
    }

    func revokeConnections() {
        authorizedOwnerUserIdentifier = nil
        authorizationGeneration = UUID()
    }

    func reload() async {
        await acquireOperation()
        defer { releaseOperation() }

        do {
            let managers = try await loadManagers()
            manager = managers.first { candidate in
                guard let tunnelProtocol = candidate.protocolConfiguration
                        as? NETunnelProviderProtocol else {
                    return false
                }
                return tunnelProtocol.providerBundleIdentifier
                    == AppConfiguration.current.packetTunnelBundleIdentifier
            }
            status = manager?.connection.status ?? .invalid
            errorMessage = nil
        } catch {
            present(error)
        }
    }

    func toggleConnection(
        expectedOwnerUserIdentifier: String,
        expectedAuthorizationGeneration: UUID
    ) async {
        switch status {
        case .connected, .connecting, .reasserting:
            await disconnect()
        default:
            await connect(
                expectedOwnerUserIdentifier: expectedOwnerUserIdentifier,
                expectedAuthorizationGeneration: expectedAuthorizationGeneration
            )
        }
    }

    func install(
        configuration: TunnelConfiguration,
        expectedAuthorizationGeneration: UUID
    ) async throws {
        await acquireOperation()
        defer { releaseOperation() }

        guard configuration.isValid,
              let credentialRecord = configuration.credentialRecord else {
            throw VPNManagerError.invalidConfiguration
        }
        try validateConnectionAuthorization(
            ownerUserIdentifier: configuration.ownerUserIdentifier,
            generation: expectedAuthorizationGeneration
        )

        let previousCredentialReference = configuredCredentialReference
        let candidate = manager ?? NETunnelProviderManager()
        let previousProtocolConfiguration = candidate.protocolConfiguration
        let previousLocalizedDescription = candidate.localizedDescription
        let previousIsEnabled = candidate.isEnabled
        if candidate.connection.status != .disconnected,
           candidate.connection.status != .invalid {
            candidate.connection.stopVPNTunnel()
        }

        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = AppConfiguration.current.packetTunnelBundleIdentifier
        tunnelProtocol.serverAddress = configuration.serverAddress
        tunnelProtocol.providerConfiguration = configuration.providerConfiguration

        try credentialStore.save(
            credentialRecord,
            reference: configuration.credentialReference
        )
        candidate.protocolConfiguration = tunnelProtocol
        candidate.localizedDescription = "ClashX VPN"
        candidate.isEnabled = true
        do {
            try await save(candidate)
        } catch {
            candidate.protocolConfiguration = previousProtocolConfiguration
            candidate.localizedDescription = previousLocalizedDescription
            candidate.isEnabled = previousIsEnabled
            try? credentialStore.delete(
                reference: configuration.credentialReference
            )
            throw error
        }

        manager = candidate
        status = candidate.connection.status
        errorMessage = nil

        if let previousCredentialReference,
           previousCredentialReference != configuration.credentialReference {
            try? credentialStore.delete(reference: previousCredentialReference)
        }

        // Saving is the commit point. If the subsequent reload fails, keep the
        // new credential because the persisted manager already references it.
        try await load(candidate)
        try validateConnectionAuthorization(
            ownerUserIdentifier: configuration.ownerUserIdentifier,
            generation: expectedAuthorizationGeneration
        )
    }

    func disconnect() async {
        await acquireOperation()
        defer { releaseOperation() }

        guard let manager else {
            status = .invalid
            return
        }

        manager.connection.stopVPNTunnel()
        status = manager.connection.status
        errorMessage = nil
    }

    func removeConfiguration() async throws {
        // Revoke synchronously before the first suspension point so queued
        // installs/connects cannot outlive logout or an account switch.
        revokeConnections()
        await acquireOperation()
        defer { releaseOperation() }

        var firstError: Error?
        let managerToRemove = manager
        managerToRemove?.connection.stopVPNTunnel()

        do {
            try credentialStore.deleteAll()
        } catch {
            firstError = error
        }

        if let managerToRemove {
            do {
                try await remove(managerToRemove)
                if manager === managerToRemove {
                    manager = nil
                }
            } catch {
                firstError = firstError ?? error
            }
        }

        status = manager?.connection.status ?? .invalid
        errorMessage = nil
        if let firstError {
            throw firstError
        }
    }

    private func connect(
        expectedOwnerUserIdentifier: String,
        expectedAuthorizationGeneration: UUID
    ) async {
        await acquireOperation()
        defer { releaseOperation() }

        do {
            guard let manager else {
                throw VPNManagerError.notConfigured
            }
            try await load(manager)
            try validateConnectionAuthorization(
                ownerUserIdentifier: expectedOwnerUserIdentifier,
                generation: expectedAuthorizationGeneration
            )
            guard configuredOwnerUserIdentifier == expectedOwnerUserIdentifier,
                  let credentialReference = configuredCredentialReference else {
                throw VPNManagerError.accountMismatch
            }
            let credential = try credentialStore.load(
                reference: credentialReference
            )
            guard credential.ownerUserIdentifier == expectedOwnerUserIdentifier,
                  credential.nodeIdentifier == configuredNodeIdentifier,
                  credential.serverAddress == configuredServerAddress else {
                throw VPNManagerError.accountMismatch
            }
            try manager.connection.startVPNTunnel()
            status = manager.connection.status
            errorMessage = nil
        } catch {
            present(error)
        }
    }

    private func validateConnectionAuthorization(
        ownerUserIdentifier: String,
        generation: UUID
    ) throws {
        guard authorizedOwnerUserIdentifier == ownerUserIdentifier,
              authorizationGeneration == generation else {
            throw VPNManagerError.authorizationRevoked
        }
    }

    private func acquireOperation() async {
        pendingOperationCount += 1
        isBusy = true
        guard operationLocked else {
            operationLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        pendingOperationCount = max(0, pendingOperationCount - 1)
        if operationWaiters.isEmpty {
            operationLocked = false
        } else {
            operationWaiters.removeFirst().resume()
        }
        isBusy = pendingOperationCount > 0
    }

    private func loadManagers() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
    }

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func load(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func remove(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.removeFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }
}

enum VPNManagerError: LocalizedError {
    case invalidConfiguration
    case notConfigured
    case accountMismatch
    case authorizationRevoked

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "节点配置无效"
        case .notConfigured:
            return "请先登录并选择可用节点"
        case .accountMismatch:
            return "VPN 配置属于其他登录会话，请重新选择节点"
        case .authorizationRevoked:
            return "当前登录会话已变化，VPN 连接已取消"
        }
    }
}
