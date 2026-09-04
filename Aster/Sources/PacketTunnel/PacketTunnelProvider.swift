import Foundation
import Libbox
import NetworkExtension
import OSLog

enum PacketTunnelLog {
    static let logger = Logger(
        subsystem: "com.astervpn.Aster.PacketTunnel",
        category: "Lifecycle"
    )
}

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var boxService: LibboxCommandServer?
    private lazy var platformInterface = PacketTunnelPlatformInterface(tunnel: self)
    private var dataPlaneReady = false

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // Libbox setup can synchronously wait on Go runtime initialization and
        // network callbacks. Keep it off the extension's XPC/main thread so
        // iOS does not terminate the provider while handling the start command.
        Task { [weak self] in
            guard let self else { return }
            self.dataPlaneReady = false
            PacketTunnelLog.logger.notice("startTunnel entered")

            var loadedConfiguration: TunnelConfiguration?
            do {
                let configuration = try TunnelConfigManager.loadConfig()
                loadedConfiguration = configuration
                if configuration.resolvedServerAddresses.isEmpty {
                    // Legacy configs may already contain a numeric endpoint;
                    // accept that without reintroducing DNS inside the
                    // full-tunnel extension.
                    self.platformInterface.setEndpointAddress(configuration.serverAddress)
                } else {
                    self.platformInterface.setEndpointAddresses(configuration.resolvedServerAddresses)
                }
                PacketTunnelLog.logger.notice(
                    "Selected location protocol=\(configuration.protocolKind.rawValue, privacy: .public) port=\(configuration.serverPort, privacy: .public) tls=\(configuration.tlsEnabled, privacy: .public)"
                )
                PacketTunnelLog.logger.notice("Tunnel configuration loaded")
                let singBoxJSON = try SingBoxConfigurationBuilder.makeJSON(from: configuration)
                PacketTunnelLog.logger.notice("Sing-box configuration built")
                try self.prepareLibbox()
                PacketTunnelLog.logger.notice("Libbox setup completed")
                PacketTunnelLog.logger.notice("Validating Libbox configuration")
                try self.validateLibboxConfiguration(singBoxJSON, configuration: configuration)
                PacketTunnelLog.logger.notice("Libbox configuration validated")

                var creationError: NSError?
                let service = LibboxNewCommandServer(
                    // The bundled Libbox build includes the internal command
                    // server. Its handler is an in-process callback only; it
                    // does not publish a listener or expose a Clash API to
                    // other apps. Passing the platform object here matches
                    // the previously working integration and lets Libbox
                    // satisfy its internal service lifecycle callbacks.
                    self.platformInterface,
                    self.platformInterface,
                    &creationError
                )
                if let creationError {
                    throw creationError
                }
                guard let service else {
                    throw PacketTunnelError.serviceUnavailable
                }
                self.boxService = service
                PacketTunnelLog.logger.notice("Libbox command server created")
                try service.start()
                PacketTunnelLog.logger.notice("Libbox command server started")
                // Current Libbox dereferences OverrideOptions while translating it
                // to the daemon model. Passing nil terminates the Go runtime instead
                // of returning an NSError, so always provide an explicit instance.
                let overrideOptions = LibboxOverrideOptions()
                overrideOptions.autoRedirect = false
                try service.startOrReloadService(singBoxJSON, options: overrideOptions)
                PacketTunnelLog.logger.notice("Libbox service started")
                self.dataPlaneReady = true
                completionHandler(nil)
            } catch {
                let rawMessage = (error as NSError).localizedDescription
                let diagnostic = if let loadedConfiguration {
                    self.redactedDiagnostic(rawMessage, configuration: loadedConfiguration)
                } else {
                    String(rawMessage.prefix(1_024))
                }
                PacketTunnelLog.logger.error(
                    "Tunnel startup failed: \(diagnostic, privacy: .public)"
                )
                try? self.boxService?.closeService()
                self.boxService?.close()
                self.boxService = nil
                self.platformInterface.reset()
                self.removeLibboxCommandSocket()
                self.dataPlaneReady = false
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        PacketTunnelLog.logger.notice("stopTunnel entered (reason: \(reason.rawValue, privacy: .public))")
        dataPlaneReady = false
        try? boxService?.closeService()
        boxService?.close()
        boxService = nil
        platformInterface.reset()
        removeLibboxCommandSocket()
        completionHandler()
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)? = nil
    ) {
        guard
            let request = try? TunnelProviderMessageCodec.decodeRequest(messageData),
            request.command == .readiness
        else {
            completionHandler?(nil)
            return
        }

        completionHandler?(
            try? TunnelProviderMessageCodec.makeStatus(dataPlaneReady: dataPlaneReady)
        )
    }

    private func prepareLibbox() throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupName
        ) else {
            throw TunnelConfigError.appGroupUnavailable
        }

        // Keep the runtime path short: Libbox creates `command.sock` below
        // basePath, and iOS enforces a tight Unix-domain socket path limit.
        // A per-launch nested UUID directory can exceed that limit. The
        // extension is single-owner, so reuse the short directory and remove
        // only the stale command socket before setup.
        let baseURL = container.appendingPathComponent("libbox", isDirectory: true)
        let workingURL = baseURL.appendingPathComponent("working", isDirectory: true)
        PacketTunnelLog.logger.notice("Preparing Libbox runtime directory")
        try FileManager.default.createDirectory(
            at: workingURL,
            withIntermediateDirectories: true
        )
        removeLibboxCommandSocket(at: baseURL)

        let options = LibboxSetupOptions()
        options.basePath = baseURL.path
        options.workingPath = workingURL.path
        options.tempPath = FileManager.default.temporaryDirectory.path
        // Libbox's debug mode enables additional platform probes that are not
        // required by the packet tunnel and can abort the extension on-device
        // while the default-interface monitor is being initialized. Keep the
        // engine in its production mode for both Debug and Release builds;
        // lifecycle diagnostics remain available through PacketTunnelLog.
        options.logMaxLines = 0
        options.debug = false

        var setupError: NSError?
        guard LibboxSetup(options, &setupError) else {
            throw setupError ?? PacketTunnelError.serviceUnavailable
        }
        PacketTunnelLog.logger.notice("Libbox setup returned successfully")
    }

    private func removeLibboxCommandSocket(at baseURL: URL? = nil) {
        let root = baseURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupName
        )?.appendingPathComponent("libbox", isDirectory: true)
        guard let root else { return }
        try? FileManager.default.removeItem(
            at: root.appendingPathComponent("command.sock")
        )
    }

    private func validateLibboxConfiguration(
        _ content: String,
        configuration: TunnelConfiguration
    ) throws {
        var validationError: NSError?
        guard LibboxCheckConfig(content, &validationError) else {
            if let validationError {
                let diagnostic = redactedDiagnostic(
                    validationError.localizedDescription,
                    configuration: configuration
                )
                PacketTunnelLog.logger.error(
                    "Libbox rejected configuration: \(diagnostic, privacy: .public)"
                )
            }
            throw validationError ?? PacketTunnelError.invalidConfiguration
        }
    }

    private func redactedDiagnostic(
        _ message: String,
        configuration: TunnelConfiguration
    ) -> String {
        var result = message
        let sensitiveValues = [
            configuration.serverAddress,
            configuration.uuid,
            configuration.anyTLSPassword,
            configuration.serverName,
            configuration.realityPublicKey,
            configuration.realityShortID
        ].compactMap { $0 } + Array(configuration.websocketHeaders.values)

        for value in sensitiveValues where !value.isEmpty {
            result = result.replacingOccurrences(of: value, with: "<redacted>")
        }
        return String(result.prefix(1_024))
    }
}

private enum PacketTunnelError: LocalizedError {
    case serviceUnavailable
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "The VPN engine couldn't be initialized."
        case .invalidConfiguration:
            return "The selected VPN configuration isn't supported."
        }
    }
}
