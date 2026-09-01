import Foundation
@preconcurrency import Libbox
import Network
import NetworkExtension

final class PacketTunnelPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {
    private unowned let tunnel: NEPacketTunnelProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var pathMonitor: NWPathMonitor?

    init(tunnel: NEPacketTunnelProvider) {
        self.tunnel = tunnel
    }

    func openTun(
        _ options: LibboxTunOptionsProtocol?,
        ret0_: UnsafeMutablePointer<Int32>?
    ) throws {
        PacketTunnelLog.logger.notice("openTun entered")
        guard let options, let ret0_ else {
            throw PacketTunnelPlatformError.invalidTunOptions
        }

        let settings = try makeNetworkSettings(from: options)
        PacketTunnelLog.logger.notice("Tunnel network settings built")
        try apply(settings)
        PacketTunnelLog.logger.notice("Tunnel network settings applied")
        networkSettings = settings

        // Use the public Libbox binding. Its Darwin implementation locates
        // the Network Extension's utun descriptor via system socket APIs;
        // do not introspect NEPacketTunnelFlow implementation details.
        let descriptor = LibboxGetTunnelFileDescriptor()
        guard descriptor >= 0 else {
            throw PacketTunnelPlatformError.missingTunnelFileDescriptor
        }
        ret0_.pointee = descriptor
        PacketTunnelLog.logger.notice("Tunnel file descriptor delivered")
    }

    func autoDetectControl(_ fd: Int32) throws {}

    func usePlatformAutoDetectControl() -> Bool { false }

    func useProcFS() -> Bool { false }

    func underNetworkExtension() -> Bool { true }

    func includeAllNetworks() -> Bool { false }

    func localDNSTransport() -> (any LibboxLocalDNSTransportProtocol)? { nil }

    func systemCertificates() -> (any LibboxStringIteratorProtocol)? { nil }

    func readWIFIState() -> LibboxWIFIState? { nil }

    func findConnectionOwner(
        _ ipProtocol: Int32,
        sourceAddress: String?,
        sourcePort: Int32,
        destinationAddress: String?,
        destinationPort: Int32
    ) throws -> LibboxConnectionOwner {
        throw PacketTunnelPlatformError.connectionOwnerUnavailable
    }

    func send(_ notification: LibboxNotification?) throws {}

    func cancelNotification(_ identifier: String?, typeID: Int32) throws {}

    func registerMyInterface(_ name: String?) {}

    func startNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws {}

    func closeNeighborMonitor(_ listener: LibboxNeighborUpdateListenerProtocol?) throws {}

    func tailscaleHostname() -> String { "" }

    func usePlatformBridge() -> Bool { false }

    func createBridge(
        _ options: LibboxBridgeOptions?
    ) throws -> any LibboxBridgeSessionProtocol {
        throw PacketTunnelPlatformError.unsupportedPlatformFeature
    }

    func usePlatformShell() -> Bool { false }

    func checkPlatformShell() throws {
        throw PacketTunnelPlatformError.unsupportedPlatformFeature
    }

    func lookupUser(_ username: String?) throws -> LibboxPlatformUser {
        throw PacketTunnelPlatformError.unsupportedPlatformFeature
    }

    func openShellSession(
        _ user: LibboxPlatformUser?,
        command: String?,
        environ: LibboxStringIteratorProtocol?,
        term: String?,
        rows: Int32,
        cols: Int32
    ) throws -> any LibboxShellSessionProtocol {
        throw PacketTunnelPlatformError.unsupportedPlatformFeature
    }

    func lookupSFTPServer(_ error: NSErrorPointer) -> String { "" }

    func readSystemSSHHostKey(_ error: NSErrorPointer) -> String { "" }

    func clearDNSCache() {
        guard let networkSettings else { return }
        tunnel.reasserting = true
        defer { tunnel.reasserting = false }
        try? apply(nil)
        try? apply(networkSettings)
    }

    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        PacketTunnelLog.logger.notice("Default interface monitor requested")
        guard let listener else { return }
        pathMonitor?.cancel()

        let monitor = NWPathMonitor()
        pathMonitor = monitor
        let firstUpdate = DispatchSemaphore(value: 0)
        let deliveredFirstUpdate = LockedBox(false)
        monitor.pathUpdateHandler = { path in
            Self.publish(path, to: listener)
            let shouldSignal = deliveredFirstUpdate.withValue { delivered in
                guard !delivered else { return false }
                delivered = true
                return true
            }
            if shouldSignal {
                firstUpdate.signal()
            }
        }
        // Keep the monitor on a system utility queue. A private serial queue
        // can re-enter Libbox's callback bridge while it is synchronously
        // waiting for the first update, which aborts the extension on device.
        monitor.start(queue: DispatchQueue.global(qos: .utility))

        guard firstUpdate.wait(timeout: .now() + 5) == .success else {
            monitor.cancel()
            pathMonitor = nil
            throw PacketTunnelPlatformError.networkPathUnavailable
        }
        PacketTunnelLog.logger.notice("Default interface monitor ready")
    }

    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        guard let pathMonitor else {
            throw PacketTunnelPlatformError.networkMonitorUnavailable
        }
        let interfaces: [LibboxNetworkInterface] = pathMonitor.currentPath.availableInterfaces.map {
            let value = LibboxNetworkInterface()
            value.name = $0.name
            value.index = Int32($0.index)
            switch $0.type {
            case .wifi:
                value.type = LibboxInterfaceTypeWIFI
            case .cellular:
                value.type = LibboxInterfaceTypeCellular
            case .wiredEthernet:
                value.type = LibboxInterfaceTypeEthernet
            default:
                value.type = LibboxInterfaceTypeOther
            }
            return value
        }
        return PacketTunnelNetworkInterfaceIterator(interfaces)
    }

    func reset() {
        pathMonitor?.cancel()
        pathMonitor = nil
        networkSettings = nil
    }

    private func makeNetworkSettings(
        from options: LibboxTunOptionsProtocol
    ) throws -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: options.getMTU())

        let dnsIterator = try options.getDNSServerAddress()
        var dnsServers: [String] = []
        while dnsIterator.hasNext() {
            let server = dnsIterator.next()
            if !server.isEmpty {
                dnsServers.append(server)
            }
        }
        if !dnsServers.isEmpty {
            let dnsSettings = NEDNSSettings(servers: dnsServers)
            dnsSettings.matchDomains = [""]
            dnsSettings.matchDomainsNoSearch = true
            settings.dnsSettings = dnsSettings
        }

        if let addressIterator = options.getInet4Address() {
            var addresses: [String] = []
            var masks: [String] = []
            while addressIterator.hasNext(), let prefix = addressIterator.next() {
                addresses.append(prefix.address())
                masks.append(prefix.mask())
            }

            if !addresses.isEmpty {
                let ipv4 = NEIPv4Settings(addresses: addresses, subnetMasks: masks)
                ipv4.includedRoutes = Self.ipv4Routes(
                    from: options.getInet4RouteAddress(),
                    defaultsWhenEmpty: options.getAutoRoute()
                )
                ipv4.excludedRoutes = Self.ipv4Routes(
                    from: options.getInet4RouteExcludeAddress(),
                    defaultsWhenEmpty: false
                )
                settings.ipv4Settings = ipv4
            }
        }

        if let addressIterator = options.getInet6Address() {
            var addresses: [String] = []
            var prefixLengths: [NSNumber] = []
            while addressIterator.hasNext(), let prefix = addressIterator.next() {
                addresses.append(prefix.address())
                prefixLengths.append(NSNumber(value: prefix.prefix()))
            }

            if !addresses.isEmpty {
                let ipv6 = NEIPv6Settings(
                    addresses: addresses,
                    networkPrefixLengths: prefixLengths
                )
                ipv6.includedRoutes = Self.ipv6Routes(
                    from: options.getInet6RouteAddress(),
                    defaultsWhenEmpty: options.getAutoRoute()
                )
                ipv6.excludedRoutes = Self.ipv6Routes(
                    from: options.getInet6RouteExcludeAddress(),
                    defaultsWhenEmpty: false
                )
                settings.ipv6Settings = ipv6
            }
        }

        guard settings.ipv4Settings != nil || settings.ipv6Settings != nil else {
            throw PacketTunnelPlatformError.missingTunnelAddress
        }
        return settings
    }

    private func apply(_ settings: NEPacketTunnelNetworkSettings?) throws {
        let completed = DispatchSemaphore(value: 0)
        let applyError = LockedBox<Error?>(nil)

        tunnel.setTunnelNetworkSettings(settings) { error in
            applyError.withValue { $0 = error }
            completed.signal()
        }

        guard completed.wait(timeout: .now() + 10) == .success else {
            throw PacketTunnelPlatformError.networkSettingsTimedOut
        }
        if let error = applyError.value {
            throw error
        }
    }

    private static func ipv4Routes(
        from iterator: (any LibboxRoutePrefixIteratorProtocol)?,
        defaultsWhenEmpty: Bool
    ) -> [NEIPv4Route] {
        var routes: [NEIPv4Route] = []
        while iterator?.hasNext() == true, let prefix = iterator?.next() {
            routes.append(
                NEIPv4Route(
                    destinationAddress: prefix.address(),
                    subnetMask: prefix.mask()
                )
            )
        }
        if routes.isEmpty, defaultsWhenEmpty {
            routes.append(.default())
        }
        return routes
    }

    private static func ipv6Routes(
        from iterator: (any LibboxRoutePrefixIteratorProtocol)?,
        defaultsWhenEmpty: Bool
    ) -> [NEIPv6Route] {
        var routes: [NEIPv6Route] = []
        while iterator?.hasNext() == true, let prefix = iterator?.next() {
            routes.append(
                NEIPv6Route(
                    destinationAddress: prefix.address(),
                    networkPrefixLength: NSNumber(value: prefix.prefix())
                )
            )
        }
        if routes.isEmpty, defaultsWhenEmpty {
            routes.append(.default())
        }
        return routes
    }

    private static func publish(
        _ path: Network.NWPath,
        to listener: LibboxInterfaceUpdateListenerProtocol
    ) {
        guard path.status != .unsatisfied, let interface = path.availableInterfaces.first else {
            listener.updateDefaultInterface(
                "",
                interfaceIndex: -1,
                isExpensive: false,
                isConstrained: false
            )
            return
        }
        listener.updateDefaultInterface(
            interface.name,
            interfaceIndex: Int32(interface.index),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }
}

private final class PacketTunnelNetworkInterfaceIterator: NSObject, LibboxNetworkInterfaceIteratorProtocol {
    private var iterator: IndexingIterator<[LibboxNetworkInterface]>
    private var nextValue: LibboxNetworkInterface?

    init(_ interfaces: [LibboxNetworkInterface]) {
        iterator = interfaces.makeIterator()
    }

    func hasNext() -> Bool {
        nextValue = iterator.next()
        return nextValue != nil
    }

    func next() -> LibboxNetworkInterface? {
        defer { nextValue = nil }
        return nextValue
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    @discardableResult
    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&storage)
    }
}


private enum PacketTunnelPlatformError: LocalizedError {
    case invalidTunOptions
    case missingTunnelAddress
    case missingTunnelFileDescriptor
    case networkMonitorUnavailable
    case networkPathUnavailable
    case networkSettingsTimedOut
    case connectionOwnerUnavailable
    case unsupportedPlatformFeature

    var errorDescription: String? {
        switch self {
        case .invalidTunOptions:
            return "The VPN engine supplied invalid tunnel options."
        case .missingTunnelAddress:
            return "The VPN engine did not supply a tunnel address."
        case .missingTunnelFileDescriptor:
            return "The VPN tunnel file descriptor is unavailable."
        case .networkMonitorUnavailable:
            return "The device network monitor isn't running."
        case .networkPathUnavailable:
            return "The device network path is unavailable."
        case .networkSettingsTimedOut:
            return "Applying VPN network settings timed out."
        case .connectionOwnerUnavailable:
            return "Connection owner lookup is unavailable on iOS."
        case .unsupportedPlatformFeature:
            return "This optional platform feature is unavailable in Aster."
        }
    }
}
