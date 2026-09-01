import Combine
@preconcurrency import Foundation
@preconcurrency import NetworkExtension

@MainActor
final class VPNManager: ObservableObject {
    static let shared = VPNManager()

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var isReady = false
    @Published private(set) var isDataPlaneReady = false
    @Published private(set) var userMessage: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: VPNUncheckedSendableBox<NSObjectProtocol>?
    private var readinessTask: Task<Void, Never>?
    private var hasLoadedManager = false
    private var isLoadingManager = false
    private var pendingConnect = false

    private init() {
        // Loading/saving a NETunnelProviderManager can trigger Apple's VPN
        // permission flow. Defer it until the user explicitly taps Connect.
    }

    deinit {
        readinessTask?.cancel()
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver.value)
        }
    }

    func connect() {
        userMessage = nil
        resetDataPlaneReadiness()

        guard let manager, isReady else {
            pendingConnect = true
            loadManagerIfNeeded()
            return
        }

        do {
            _ = try TunnelConfigManager.loadConfig()
            try manager.connection.startVPNTunnel()
        } catch let error as TunnelConfigError {
            userMessage = error.localizedDescription
        } catch {
            userMessage = Self.userMessage(for: error)
        }
    }

    func disconnect() {
        resetDataPlaneReadiness()
        manager?.connection.stopVPNTunnel()
    }

    func clearMessage() {
        userMessage = nil
    }

    func reload() {
        userMessage = nil
        isReady = false
        manager = nil
        hasLoadedManager = false
        loadManagerIfNeeded()
    }

    private func loadManagerIfNeeded() {
        guard !hasLoadedManager, !isLoadingManager else { return }
        isLoadingManager = true
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            let result = VPNUncheckedSendableBox((managers, error))
            Task { @MainActor in
                guard let self else { return }
                let (managers, error) = result.value
                if let error {
                    self.status = .invalid
                    self.userMessage = Self.userMessage(for: error)
                    self.finishManagerLoad()
                    return
                }

                if let existing = managers?.first {
                    self.install(existing)
                    self.finishManagerLoad()
                } else {
                    self.createManager()
                }
            }
        }
    }

    private func createManager() {
        let newManager = NETunnelProviderManager()
        newManager.localizedDescription = "Aster VPN"

        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = "com.astervpn.Aster.PacketTunnel"
        protocolConfiguration.serverAddress = "Aster Secure Network"
        newManager.protocolConfiguration = protocolConfiguration
        newManager.isEnabled = true

        newManager.saveToPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.status = .invalid
                    self.userMessage = Self.userMessage(for: error)
                    self.finishManagerLoad()
                    return
                }
                newManager.loadFromPreferences { loadError in
                    Task { @MainActor in
                        if let loadError {
                            self.status = .invalid
                            self.userMessage = Self.userMessage(for: loadError)
                        } else {
                            self.install(newManager)
                        }
                        self.finishManagerLoad()
                    }
                }
            }
        }
    }

    private func finishManagerLoad() {
        isLoadingManager = false
        hasLoadedManager = true
        guard pendingConnect else { return }
        pendingConnect = false
        connect()
    }

    private func install(_ manager: NETunnelProviderManager) {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver.value)
        }

        self.manager = manager
        isReady = manager.isEnabled
        handleStatusChange(manager.connection.status)
        let managerBox = VPNUncheckedSendableBox(manager)
        let observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self, managerBox] _ in
            Task { @MainActor in
                guard let self else { return }
                self.handleStatusChange(managerBox.value.connection.status)
            }
        }
        statusObserver = VPNUncheckedSendableBox(observer)
    }

    private func handleStatusChange(_ newStatus: NEVPNStatus) {
        status = newStatus
        if newStatus == .connected {
            beginDataPlaneReadinessProbe()
        } else {
            resetDataPlaneReadiness()
        }

        if newStatus == .invalid {
            userMessage = "VPN permission or configuration is unavailable."
        }
    }

    private func beginDataPlaneReadinessProbe() {
        resetDataPlaneReadiness()
        readinessTask = Task { [weak self] in
            for _ in 0..<10 {
                guard let self, !Task.isCancelled, self.status == .connected else { return }
                if await self.requestProviderReadiness() {
                    self.isDataPlaneReady = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }

            guard let self, !Task.isCancelled, self.status == .connected else { return }
            self.userMessage = "Aster couldn't confirm that the secure tunnel is ready. Please try again."
            self.manager?.connection.stopVPNTunnel()
        }
    }

    private func resetDataPlaneReadiness() {
        readinessTask?.cancel()
        readinessTask = nil
        isDataPlaneReady = false
    }

    private func requestProviderReadiness() async -> Bool {
        guard
            status == .connected,
            let session = manager?.connection as? NETunnelProviderSession,
            let request = try? TunnelProviderMessageCodec.makeReadinessRequest()
        else {
            return false
        }

        return await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(request) { response in
                    guard
                        let response,
                        let providerStatus = try? TunnelProviderMessageCodec.decodeStatus(response)
                    else {
                        continuation.resume(returning: false)
                        return
                    }
                    continuation.resume(returning: providerStatus.dataPlaneReady)
                }
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    private static func userMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NEVPNErrorDomain {
            return "Aster couldn't update VPN permission. Please open Settings and try again."
        }
        return "Aster couldn't start the secure connection. Please try again."
    }
}

private final class VPNUncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
