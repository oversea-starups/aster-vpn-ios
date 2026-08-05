import Foundation
import Libbox
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: LibboxCommandServer?
    private var platformInterface: SingBoxPlatformInterface?
    private var activeConfiguration: String?

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        Task {
            do {
                let configuration = try loadConfiguration()
                try startCore(configuration: configuration)
                completionHandler(nil)
            } catch {
                stopCore()
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        stopCore()
        completionHandler()
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        commandServer?.pause()
        completionHandler()
    }

    override func wake() {
        commandServer?.resetNetwork()
    }

    func stopCore() {
        if let commandServer {
            try? commandServer.closeService()
            commandServer.close()
        }
        commandServer = nil
        activeConfiguration = nil
        platformInterface?.reset()
        platformInterface = nil
    }

    func reloadCore() throws {
        guard let commandServer, let activeConfiguration else {
            throw PacketTunnelError.serviceUnavailable
        }
        let options = LibboxOverrideOptions()
        try commandServer.startOrReloadService(
            activeConfiguration,
            options: options
        )
    }

    private func loadConfiguration() throws -> String {
        guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfiguration = tunnelProtocol.providerConfiguration,
              providerConfiguration["schemaVersion"] as? Int == 1,
              let serverAddress = providerConfiguration["serverAddress"] as? String,
              let nodeIdentifier = providerConfiguration["nodeIdentifier"] as? String,
              let ownerUserIdentifier = providerConfiguration["ownerUserIdentifier"] as? String,
              let credentialReference = providerConfiguration["credentialReference"] as? String else {
            throw PacketTunnelError.invalidConfiguration
        }

        let record = try KeychainTunnelCredentialStore().load(
            reference: credentialReference
        )
        guard record.ownerUserIdentifier == ownerUserIdentifier,
              record.nodeIdentifier == nodeIdentifier,
              record.serverAddress == serverAddress,
              !record.nodeData.isEmpty else {
            throw PacketTunnelError.invalidConfiguration
        }

        let node: VPNNode
        do {
            node = try JSONDecoder().decode(VPNNode.self, from: record.nodeData)
        } catch {
            throw PacketTunnelError.invalidConfiguration
        }
        guard node.id == nodeIdentifier,
              node.serverAddress == serverAddress else {
            throw PacketTunnelError.invalidConfiguration
        }
        return try SingBoxConfigurationBuilder.makeConfiguration(for: node)
    }

    private func startCore(configuration: String) throws {
        let paths = try makeRuntimePaths()
        let setupOptions = LibboxSetupOptions()
        setupOptions.basePath = paths.base.path
        setupOptions.workingPath = paths.working.path
        setupOptions.tempPath = paths.temporary.path
        setupOptions.logMaxLines = 200
        setupOptions.debug = false

        var setupError: NSError?
        LibboxSetup(setupOptions, &setupError)
        if let setupError {
            throw PacketTunnelError.engine(setupError.localizedDescription)
        }

        var checkError: NSError?
        LibboxCheckConfig(configuration, &checkError)
        if let checkError {
            throw PacketTunnelError.engine(checkError.localizedDescription)
        }

        let platform = SingBoxPlatformInterface(provider: self)
        var serverError: NSError?
        guard let server = LibboxNewCommandServer(
            platform,
            platform,
            &serverError
        ) else {
            throw PacketTunnelError.engine(
                serverError?.localizedDescription ?? "Unable to create the VPN engine."
            )
        }
        if let serverError {
            throw PacketTunnelError.engine(serverError.localizedDescription)
        }

        do {
            try server.start()
            try server.startOrReloadService(
                configuration,
                options: LibboxOverrideOptions()
            )
        } catch {
            server.close()
            throw PacketTunnelError.engine(error.localizedDescription)
        }

        platformInterface = platform
        commandServer = server
        activeConfiguration = configuration
    }

    private func makeRuntimePaths() throws -> (
        base: URL,
        working: URL,
        temporary: URL
    ) {
        let fileManager = FileManager.default
        let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("AsterPacketTunnel", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent(
                "AsterPacketTunnel",
                isDirectory: true
            )
        let working = root.appendingPathComponent("working", isDirectory: true)
        let temporary = fileManager.temporaryDirectory.appendingPathComponent(
            "AsterPacketTunnel",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: working,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: temporary,
            withIntermediateDirectories: true
        )
        return (root, working, temporary)
    }
}

enum PacketTunnelError: LocalizedError {
    case invalidConfiguration
    case serviceUnavailable
    case engine(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The packet tunnel configuration is invalid."
        case .serviceUnavailable:
            return "The packet tunnel service is not running."
        case let .engine(message):
            return "The VPN engine could not start: \(message)"
        }
    }
}
