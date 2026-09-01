import Combine
@preconcurrency import Foundation
@preconcurrency import NetworkExtension
import OSLog

private let vpnLogger = Logger(
    subsystem: "com.astervpn.Aster",
    category: "VPNManager"
)

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
    private var connectionTimeoutTask: Task<Void, Never>?
    private var hasLoadedManager = false
    private var isLoadingManager = false
    private var pendingConnect = false
    private var connectionAttemptInFlight = false
    private var disconnectRequested = false

    private init() {
        // Loading/saving a NETunnelProviderManager can trigger Apple's VPN
        // permission flow. Defer it until the user explicitly taps Connect.
    }

    deinit {
        readinessTask?.cancel()
        connectionTimeoutTask?.cancel()
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver.value)
        }
    }

    func connect() {
        userMessage = nil
        resetDataPlaneReadiness()
        disconnectRequested = false
        connectionAttemptInFlight = true
        vpnLogger.notice(
            "Connect requested; managerLoaded=\(self.manager != nil, privacy: .public) ready=\(self.isReady, privacy: .public) status=\(self.status.rawValue, privacy: .public)"
        )

        guard let manager, isReady else {
            pendingConnect = true
            vpnLogger.notice("VPN manager unavailable; loading preferences")
            loadManagerIfNeeded()
            return
        }

        do {
            _ = try TunnelConfigManager.loadConfig()
            try manager.connection.startVPNTunnel()
            vpnLogger.notice("startVPNTunnel accepted by Network Extension")
            scheduleConnectionTimeout()
        } catch let error as TunnelConfigError {
            connectionAttemptInFlight = false
            userMessage = error.localizedDescription
            vpnLogger.error("Tunnel config rejected before start: \(error.localizedDescription, privacy: .public)")
        } catch {
            connectionAttemptInFlight = false
            userMessage = Self.userMessage(for: error)
            let nsError = error as NSError
            vpnLogger.error(
                "startVPNTunnel failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(String(nsError.localizedDescription.prefix(256)), privacy: .public)"
            )
        }
    }

    func disconnect() {
        disconnectRequested = true
        connectionAttemptInFlight = false
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
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
                    let nsError = error as NSError
                    vpnLogger.error(
                        "loadAllFromPreferences failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
                    )
                    self.finishManagerLoad()
                    return
                }

                let expectedProviderID = "com.astervpn.Aster.PacketTunnel"
                if let existing = managers?.first(where: {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == expectedProviderID
                }) {
                    vpnLogger.notice(
                        "Found existing VPN manager; enabled=\(existing.isEnabled, privacy: .public) status=\(existing.connection.status.rawValue, privacy: .public)"
                    )
                    self.install(existing)
                    self.finishManagerLoad()
                } else {
                    vpnLogger.notice("No existing VPN manager found; creating one")
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
                    let nsError = error as NSError
                    vpnLogger.error(
                        "saveToPreferences failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
                    )
                    self.finishManagerLoad()
                    return
                }
                newManager.loadFromPreferences { loadError in
                    Task { @MainActor in
                        if let loadError {
                            self.status = .invalid
                            self.userMessage = Self.userMessage(for: loadError)
                            let nsError = loadError as NSError
                            vpnLogger.error(
                                "loadFromPreferences failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
                            )
                        } else {
                            vpnLogger.notice("New VPN manager loaded after save")
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
        let previousStatus = status
        status = newStatus
        switch newStatus {
        case .connected:
            connectionAttemptInFlight = false
            disconnectRequested = false
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            beginDataPlaneReadinessProbe()
        case .disconnected:
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            resetDataPlaneReadiness()
            if connectionAttemptInFlight && !disconnectRequested {
                userMessage = Self.connectionFailedMessage
            }
            connectionAttemptInFlight = false
            disconnectRequested = false
        default:
            resetDataPlaneReadiness()
        }

        if newStatus == .invalid {
            userMessage = "VPN permission or configuration is unavailable."
        } else if previousStatus == .connecting && newStatus == .reasserting {
            scheduleConnectionTimeout()
        }
    }

    private func scheduleConnectionTimeout() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard let self, !Task.isCancelled, self.connectionAttemptInFlight else { return }
            guard self.status == .connecting || self.status == .reasserting else { return }
            self.connectionAttemptInFlight = false
            self.userMessage = "Aster couldn't connect within 25 seconds. Please try another location."
            self.manager?.connection.stopVPNTunnel()
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

    private static func userMessage(for error: Error?) -> String {
        guard let error else {
            return "Aster couldn't establish the secure connection. Please try another location."
        }
        let nsError = error as NSError
        if nsError.domain == NEVPNErrorDomain {
            return "Aster couldn't update VPN permission. Please open Settings and try again."
        }
        return "Aster couldn't start the secure connection. Please try again."
    }

    private static let connectionFailedMessage =
        "Aster couldn't establish the secure connection. Please try another location."
}

private final class VPNUncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
