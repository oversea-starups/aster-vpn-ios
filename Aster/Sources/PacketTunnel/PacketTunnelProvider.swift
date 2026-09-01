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
        dataPlaneReady = false
        PacketTunnelLog.logger.notice("startTunnel entered")

        do {
            let configuration = try TunnelConfigManager.loadConfig()
            PacketTunnelLog.logger.notice("Tunnel configuration loaded")
            let singBoxJSON = try SingBoxConfigurationBuilder.makeJSON(from: configuration)
            PacketTunnelLog.logger.notice("Sing-box configuration built")
            try prepareLibbox()
            PacketTunnelLog.logger.notice("Libbox setup completed")
            try validateLibboxConfiguration(singBoxJSON, configuration: configuration)
            PacketTunnelLog.logger.notice("Libbox configuration validated")

            var creationError: NSError?
            let service = LibboxNewCommandServer(nil, platformInterface, &creationError)
            if let creationError {
                throw creationError
            }
            guard let service else {
                throw PacketTunnelError.serviceUnavailable
            }
            boxService = service
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
            dataPlaneReady = true
            completionHandler(nil)
        } catch {
            PacketTunnelLog.logger.error("Tunnel startup failed at a recoverable boundary")
            try? boxService?.closeService()
            boxService?.close()
            boxService = nil
            platformInterface.reset()
            dataPlaneReady = false
            completionHandler(error)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        PacketTunnelLog.logger.notice("stopTunnel entered")
        dataPlaneReady = false
        try? boxService?.closeService()
        boxService?.close()
        boxService = nil
        platformInterface.reset()
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

        let baseURL = container.appendingPathComponent("libbox", isDirectory: true)
        let workingURL = baseURL.appendingPathComponent("working", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workingURL,
            withIntermediateDirectories: true
        )

        let options = LibboxSetupOptions()
        options.basePath = baseURL.path
        options.workingPath = workingURL.path
        options.tempPath = FileManager.default.temporaryDirectory.path
        options.logMaxLines = 0
        options.debug = false

        var setupError: NSError?
        guard LibboxSetup(options, &setupError) else {
            throw setupError ?? PacketTunnelError.serviceUnavailable
        }
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
