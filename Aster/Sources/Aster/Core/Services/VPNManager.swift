import Combine
@preconcurrency import Foundation
@preconcurrency import NetworkExtension
import OSLog
import Darwin

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
    private var connectionPreparationTask: Task<Void, Never>?
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
        connectionPreparationTask?.cancel()
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

        prepareAndStartTunnel(using: manager)
    }

    func disconnect() {
        disconnectRequested = true
        connectionAttemptInFlight = false
        connectionPreparationTask?.cancel()
        connectionPreparationTask = nil
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
                    self.pendingConnect = false
                    self.connectionAttemptInFlight = false
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
                    let needsConfigurationSave = self.configureFullTunnel(existing)
                    self.install(existing, readyOverride: needsConfigurationSave ? false : nil)
                    if needsConfigurationSave {
                        self.persistFullTunnelConfiguration(existing)
                    } else {
                        self.finishManagerLoad()
                    }
                } else {
                    vpnLogger.notice("No existing VPN manager found; creating one")
                    self.createManager()
                }
            }
        }
    }

    private func createManager() {
        let newManager = NETunnelProviderManager()
        newManager.localizedDescription = "ClashX VPN"

        let protocolConfiguration = NETunnelProviderProtocol()
        protocolConfiguration.providerBundleIdentifier = "com.astervpn.Aster.PacketTunnel"
        protocolConfiguration.serverAddress = "Aster Secure Network"
        Self.applyFullTunnelSettings(to: protocolConfiguration)
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

    /// Resolve the selected proxy endpoint while the physical interface is
    /// still available. `includeAllNetworks` applies an exclusive full-tunnel
    /// policy before the packet-tunnel provider gets a chance to call
    /// `setTunnelNetworkSettings`, so resolving the hostname in the extension
    /// creates a bootstrap deadlock. The numeric addresses are persisted in
    /// the App Group config and used for both the sing-box dial target and the
    /// excluded physical-interface routes.
    private func prepareAndStartTunnel(using manager: NETunnelProviderManager) {
        connectionPreparationTask?.cancel()
        connectionPreparationTask = Task { [weak self, manager] in
            do {
                let preparedConfiguration = try await Task.detached(priority: .userInitiated) {
                    let configuration = try TunnelConfigManager.loadConfig()
                    return try TunnelEndpointResolver.prepare(configuration)
                }.value

                guard let self, !Task.isCancelled, self.connectionAttemptInFlight else { return }
                try TunnelConfigManager.saveConfig(preparedConfiguration)
                try manager.connection.startVPNTunnel()
                vpnLogger.notice(
                    "startVPNTunnel accepted with pre-resolved endpoint count=\(preparedConfiguration.resolvedServerAddresses.count, privacy: .public)"
                )
                self.scheduleConnectionTimeout()
            } catch is CancellationError {
                // A user disconnect or a newer connect request cancelled the
                // preparation. No user-facing failure should be shown.
            } catch let error as TunnelConfigError {
                guard let self, !Task.isCancelled else { return }
                self.connectionAttemptInFlight = false
                self.userMessage = error.localizedDescription
                vpnLogger.error("Tunnel config rejected before start: \(error.localizedDescription, privacy: .public)")
            } catch let error as TunnelEndpointResolutionError {
                guard let self, !Task.isCancelled else { return }
                self.connectionAttemptInFlight = false
                self.userMessage = error.localizedDescription
                vpnLogger.error("Selected proxy endpoint could not be pre-resolved")
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.connectionAttemptInFlight = false
                self.userMessage = Self.userMessage(for: error)
                let nsError = error as NSError
                vpnLogger.error(
                    "startVPNTunnel preparation failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
                )
            }
        }
    }

    private func install(
        _ manager: NETunnelProviderManager,
        readyOverride: Bool? = nil
    ) {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver.value)
        }

        self.manager = manager
        isReady = readyOverride ?? manager.isEnabled
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

    /// Ensures an existing user-installed profile is a true full tunnel. Older
    /// builds left these NEVPNProtocol flags at their iOS defaults, which can
    /// leave Safari/YouTube on a local route even though the tunnel state says
    /// connected. The provider endpoint itself is excluded by the PacketTunnel
    /// platform bridge, so enforcing all routes here does not recurse the node
    /// connection into its own TUN.
    private func configureFullTunnel(_ manager: NETunnelProviderManager) -> Bool {
        guard let protocolConfiguration = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return false
        }

        let wasConfigured = protocolConfiguration.includeAllNetworks
            && !protocolConfiguration.excludeLocalNetworks
            && protocolConfiguration.enforceRoutes
        guard !wasConfigured else { return false }

        Self.applyFullTunnelSettings(to: protocolConfiguration)
        manager.protocolConfiguration = protocolConfiguration
        return true
    }

    private static func applyFullTunnelSettings(to configuration: NETunnelProviderProtocol) {
        configuration.includeAllNetworks = true
        configuration.excludeLocalNetworks = false
        configuration.enforceRoutes = true
    }

    private func persistFullTunnelConfiguration(_ manager: NETunnelProviderManager) {
        manager.saveToPreferences { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.isReady = false
                    self.userMessage = Self.userMessage(for: error)
                    self.pendingConnect = false
                    self.connectionAttemptInFlight = false
                    self.finishManagerLoad()
                    return
                }

                manager.loadFromPreferences { loadError in
                    Task { @MainActor in
                        if let loadError {
                            self.isReady = false
                            self.userMessage = Self.userMessage(for: loadError)
                            self.pendingConnect = false
                            self.connectionAttemptInFlight = false
                        } else {
                            self.install(manager)
                        }
                        self.finishManagerLoad()
                    }
                }
            }
        }
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
            self.userMessage = "ClashX VPN couldn't connect within 25 seconds. Please try another location."
            self.manager?.connection.stopVPNTunnel()
        }
    }

    private func beginDataPlaneReadinessProbe() {
        resetDataPlaneReadiness()
        readinessTask = Task { [weak self] in
            for _ in 0..<10 {
                guard let self, !Task.isCancelled, self.status == .connected else { return }
                if await self.requestProviderReadiness() {
                    // Network Extension reports `.connected` once the provider
                    // has installed its interface. That alone does not prove
                    // that a packet completed the selected protocol handshake
                    // and reached the Internet. Verify a real HTTPS request
                    // before presenting the tunnel as protected.
                    for _ in 0..<3 {
                        if await self.probeDataPlane() {
                            self.isDataPlaneReady = true
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    vpnLogger.error("Provider is ready but HTTPS data-plane probe failed")
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }

            guard let self, !Task.isCancelled, self.status == .connected else { return }
            self.userMessage = "ClashX VPN couldn't verify Internet traffic through the secure tunnel. Please try another location."
            self.manager?.connection.stopVPNTunnel()
        }
    }

    private func probeDataPlane() async -> Bool {
        let probeURLs = [
            URL(string: "https://www.gstatic.com/generate_204"),
            URL(string: "https://www.apple.com/library/test/success.html")
        ].compactMap { $0 }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.waitsForConnectivity = false
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil
        sessionConfiguration.timeoutIntervalForRequest = 5
        sessionConfiguration.timeoutIntervalForResource = 6
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }

        for url in probeURLs {
            guard status == .connected, !Task.isCancelled else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Aster-Data-Plane-Probe/1", forHTTPHeaderField: "User-Agent")
            do {
                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                if (200..<400).contains(httpResponse.statusCode) {
                    vpnLogger.notice("HTTPS data-plane probe succeeded with status=\(httpResponse.statusCode, privacy: .public)")
                    return true
                }
                vpnLogger.error("HTTPS data-plane probe returned status=\(httpResponse.statusCode, privacy: .public)")
            } catch {
                // Do not log URLs, response bodies, or underlying errors: the
                // request is deliberately anonymous and the user needs only a
                // recoverable connection result.
                continue
            }
        }
        return false
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
            return "ClashX VPN couldn't establish the secure connection. Please try another location."
        }
        let nsError = error as NSError
        if nsError.domain == NEVPNErrorDomain {
            return "ClashX VPN couldn't update VPN permission. Please open Settings and try again."
        }
        return "ClashX VPN couldn't start the secure connection. Please try again."
    }

    private static let connectionFailedMessage =
        "ClashX VPN couldn't establish the secure connection. Please try another location."
}

private enum TunnelEndpointResolutionError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "ClashX VPN couldn't resolve the selected location before starting. Please try another location."
    }
}

private enum TunnelEndpointResolver {
    static func prepare(_ configuration: TunnelConfiguration) throws -> TunnelConfiguration {
        let addresses = try resolve(configuration.serverAddress)
        guard !addresses.isEmpty else {
            throw TunnelEndpointResolutionError.unavailable
        }
        return configuration.withResolvedServerAddresses(addresses)
    }

    private static func resolve(_ address: String) throws -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        var status = getaddrinfo(address, nil, &hints, &result)
        if status != 0 {
            // Some cellular configurations report no address-configured
            // family even though a numeric or DNS answer is usable. Retry
            // without that hint before treating the location as unavailable.
            hints.ai_flags = 0
            status = getaddrinfo(address, nil, &hints, &result)
        }
        guard status == 0, let result else {
            throw TunnelEndpointResolutionError.unavailable
        }
        defer { freeaddrinfo(result) }

        var ipv4 = Set<String>()
        var ipv6 = Set<String>()
        var cursor: UnsafeMutablePointer<addrinfo>? = result
        while let info = cursor {
            let addressInfo = info.pointee
            guard let socketAddress = addressInfo.ai_addr else {
                cursor = addressInfo.ai_next
                continue
            }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let numericStatus = hostBuffer.withUnsafeMutableBufferPointer { buffer in
                getnameinfo(
                    socketAddress,
                    addressInfo.ai_addrlen,
                    buffer.baseAddress,
                    socklen_t(buffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
            }
            if numericStatus == 0, let numericAddress = hostBuffer.withUnsafeBufferPointer({ buffer in
                buffer.baseAddress.map { String(cString: $0) }
            }) {
                if addressInfo.ai_family == AF_INET {
                    ipv4.insert(numericAddress)
                } else if addressInfo.ai_family == AF_INET6 {
                    ipv6.insert(numericAddress)
                }
            }
            cursor = addressInfo.ai_next
        }

        // Prefer IPv4 because the bundled catalog's TCP endpoints and the
        // physical route exclusion are most consistently available on both
        // Wi-Fi and cellular. Keep IPv6 answers as failover candidates.
        return ipv4.sorted() + ipv6.sorted()
    }
}

private final class VPNUncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
