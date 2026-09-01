import Foundation
import Libbox
import Network
import NetworkExtension

final class SingBoxPlatformInterface: NSObject,
    LibboxPlatformInterfaceProtocol,
    LibboxCommandServerHandlerProtocol {
    private weak var provider: PacketTunnelProvider?
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var pathMonitor: NWPathMonitor?

    init(provider: PacketTunnelProvider) {
        self.provider = provider
    }

    func openTun(
        _ options: LibboxTunOptionsProtocol?,
        ret0_: UnsafeMutablePointer<Int32>?
    ) throws {
        guard let provider, let options, let ret0_ else {
            throw PlatformInterfaceError.invalidTunnelOptions
        }

        let settings = NEPacketTunnelNetworkSettings(
            tunnelRemoteAddress: "127.0.0.1"
        )
        settings.mtu = NSNumber(value: options.getMTU())

        let dnsServer = try options.getDNSServerAddress().value
        if !dnsServer.isEmpty {
            let dns = NEDNSSettings(servers: [dnsServer])
            dns.matchDomains = [""]
            dns.matchDomainsNoSearch = true
            settings.dnsSettings = dns
        }

        let ipv4Iterator = options.getInet4Address()
        var ipv4Addresses: [String] = []
        var ipv4Masks: [String] = []
        while ipv4Iterator?.hasNext() == true {
            guard let prefix = ipv4Iterator?.next() else { continue }
            ipv4Addresses.append(prefix.address())
            ipv4Masks.append(prefix.mask())
        }
        if !ipv4Addresses.isEmpty {
            let ipv4 = NEIPv4Settings(
                addresses: ipv4Addresses,
                subnetMasks: ipv4Masks
            )
            var routes: [NEIPv4Route] = []
            let routeIterator = options.getInet4RouteAddress()
            while routeIterator?.hasNext() == true {
                guard let prefix = routeIterator?.next() else { continue }
                routes.append(
                    NEIPv4Route(
                        destinationAddress: prefix.address(),
                        subnetMask: prefix.mask()
                    )
                )
            }
            ipv4.includedRoutes = routes.isEmpty ? [.default()] : routes

            var excludedRoutes: [NEIPv4Route] = []
            let excludedIterator = options.getInet4RouteExcludeAddress()
            while excludedIterator?.hasNext() == true {
                guard let prefix = excludedIterator?.next() else { continue }
                excludedRoutes.append(
                    NEIPv4Route(
                        destinationAddress: prefix.address(),
                        subnetMask: prefix.mask()
                    )
                )
            }
            ipv4.excludedRoutes = excludedRoutes
            settings.ipv4Settings = ipv4
        }

        let ipv6Iterator = options.getInet6Address()
        var ipv6Addresses: [String] = []
        var ipv6Prefixes: [NSNumber] = []
        while ipv6Iterator?.hasNext() == true {
            guard let prefix = ipv6Iterator?.next() else { continue }
            ipv6Addresses.append(prefix.address())
            ipv6Prefixes.append(NSNumber(value: prefix.prefix()))
        }
        if !ipv6Addresses.isEmpty {
            let ipv6 = NEIPv6Settings(
                addresses: ipv6Addresses,
                networkPrefixLengths: ipv6Prefixes
            )
            var routes: [NEIPv6Route] = []
            let routeIterator = options.getInet6RouteAddress()
            while routeIterator?.hasNext() == true {
                guard let prefix = routeIterator?.next() else { continue }
                routes.append(
                    NEIPv6Route(
                        destinationAddress: prefix.address(),
                        networkPrefixLength: NSNumber(value: prefix.prefix())
                    )
                )
            }
            ipv6.includedRoutes = routes.isEmpty ? [.default()] : routes

            var excludedRoutes: [NEIPv6Route] = []
            let excludedIterator = options.getInet6RouteExcludeAddress()
            while excludedIterator?.hasNext() == true {
                guard let prefix = excludedIterator?.next() else { continue }
                excludedRoutes.append(
                    NEIPv6Route(
                        destinationAddress: prefix.address(),
                        networkPrefixLength: NSNumber(value: prefix.prefix())
                    )
                )
            }
            ipv6.excludedRoutes = excludedRoutes
            settings.ipv6Settings = ipv6
        }

        let result = apply(settings, using: provider)
        if let error = result.error {
            throw error
        }
        guard result.completed else {
            throw PlatformInterfaceError.networkSettingsTimedOut
        }

        let descriptor = LibboxGetTunnelFileDescriptor()
        guard descriptor >= 0 else {
            throw PlatformInterfaceError.missingTunnelFileDescriptor
        }
        networkSettings = settings
        ret0_.pointee = descriptor
    }

    func autoDetectControl(_ fd: Int32) throws {}

    func usePlatformAutoDetectControl() -> Bool {
        false
    }

    func startDefaultInterfaceMonitor(
        _ listener: LibboxInterfaceUpdateListenerProtocol?
    ) throws {
        guard let listener else { return }
        let monitor = NWPathMonitor()
        pathMonitor?.cancel()
        pathMonitor = monitor

        let ready = DispatchSemaphore(value: 0)
        var firstUpdate = true
        monitor.pathUpdateHandler = { [weak self] path in
            self?.publish(path: path, to: listener)
            if firstUpdate {
                firstUpdate = false
                ready.signal()
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        guard ready.wait(timeout: .now() + 5) == .success else {
            monitor.cancel()
            pathMonitor = nil
            throw PlatformInterfaceError.defaultInterfaceTimedOut
        }
    }

    func closeDefaultInterfaceMonitor(
        _ listener: LibboxInterfaceUpdateListenerProtocol?
    ) throws {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func getInterfaces() throws -> LibboxNetworkInterfaceIteratorProtocol {
        guard let pathMonitor else {
            return NetworkInterfaceIterator([])
        }
        let path = pathMonitor.currentPath
        guard path.status != .unsatisfied else {
            return NetworkInterfaceIterator([])
        }

        let interfaces = path.availableInterfaces.map { item in
            let interface = LibboxNetworkInterface()
            interface.name = item.name
            interface.index = Int32(item.index)
            switch item.type {
            case .wifi:
                interface.type = LibboxInterfaceTypeWIFI
            case .cellular:
                interface.type = LibboxInterfaceTypeCellular
            case .wiredEthernet:
                interface.type = LibboxInterfaceTypeEthernet
            default:
                interface.type = LibboxInterfaceTypeOther
            }
            interface.metered = path.isExpensive
            return interface
        }
        return NetworkInterfaceIterator(interfaces)
    }

    func findConnectionOwner(
        _ ipProtocol: Int32,
        sourceAddress: String?,
        sourcePort: Int32,
        destinationAddress: String?,
        destinationPort: Int32
    ) throws -> LibboxConnectionOwner {
        throw PlatformInterfaceError.connectionOwnerUnavailable
    }

    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }
    func useProcFS() -> Bool { false }
    func localDNSTransport() -> LibboxLocalDNSTransportProtocol? { nil }
    func systemCertificates() -> LibboxStringIteratorProtocol? { nil }
    func readWIFIState() -> LibboxWIFIState? { nil }
    func clearDNSCache() {}
    func send(_ notification: LibboxNotification?) throws {}

    func serviceStop() throws {
        provider?.stopCore()
    }

    func serviceReload() throws {
        try provider?.reloadCore()
    }

    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        LibboxSystemProxyStatus()
    }

    func setSystemProxyEnabled(_ enabled: Bool) throws {}
    func writeDebugMessage(_ message: String?) {}

    func reset() {
        networkSettings = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func publish(
        path: Network.NWPath,
        to listener: LibboxInterfaceUpdateListenerProtocol
    ) {
        guard path.status != .unsatisfied,
              let interface = path.availableInterfaces.first else {
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

    private func apply(
        _ settings: NEPacketTunnelNetworkSettings,
        using provider: PacketTunnelProvider
    ) -> (completed: Bool, error: Error?) {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var completionError: Error?
        provider.setTunnelNetworkSettings(settings) { error in
            lock.lock()
            completionError = error
            lock.unlock()
            semaphore.signal()
        }
        let completed = semaphore.wait(timeout: .now() + 15) == .success
        lock.lock()
        let error = completionError
        lock.unlock()
        return (completed, error)
    }
}

private final class NetworkInterfaceIterator: NSObject,
    LibboxNetworkInterfaceIteratorProtocol {
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
        nextValue
    }
}

private enum PlatformInterfaceError: LocalizedError {
    case invalidTunnelOptions
    case networkSettingsTimedOut
    case defaultInterfaceTimedOut
    case missingTunnelFileDescriptor
    case connectionOwnerUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidTunnelOptions:
            return "The tunnel options are invalid."
        case .networkSettingsTimedOut:
            return "Applying tunnel network settings timed out."
        case .defaultInterfaceTimedOut:
            return "Detecting the default network interface timed out."
        case .missingTunnelFileDescriptor:
            return "The tunnel file descriptor is unavailable."
        case .connectionOwnerUnavailable:
            return "Connection owner lookup is unavailable on iOS."
        }
    }
}
