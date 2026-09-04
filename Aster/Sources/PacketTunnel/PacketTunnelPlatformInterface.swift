import Foundation
@preconcurrency import Libbox
import Network
import NetworkExtension
import Darwin

final class PacketTunnelPlatformInterface: NSObject,
    LibboxPlatformInterfaceProtocol,
    LibboxCommandServerHandlerProtocol {
    private unowned let tunnel: NEPacketTunnelProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var pathMonitor: NWPathMonitor?
    private var endpointAddresses: [String] = []

    init(tunnel: NEPacketTunnelProvider) {
        self.tunnel = tunnel
    }

    /// The proxy endpoint must stay reachable through the physical interface.
    /// Once the TUN default route is installed, excluding the resolved /32 or
    /// /128 prevents the tunnel from recursively trying to reach itself.
    func setEndpointAddress(_ address: String) {
        endpointAddresses = address.isEmpty ? [] : [address]
    }

    /// Receives addresses resolved by the containing app before the exclusive
    /// full-tunnel policy is enabled. This method deliberately accepts only
    /// numeric addresses; `resolvedEndpointRoutes()` never performs DNS.
    func setEndpointAddresses(_ addresses: [String]) {
        endpointAddresses = addresses
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

    // The app configures NETunnelProviderProtocol as a full-tunnel profile.
    // Keep Libbox's platform view in sync so its route calculation does not
    // preserve a split-tunnel interpretation on iOS.
    func includeAllNetworks() -> Bool { true }

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

    func send(_ notification: LibboxNotification?) throws {
        // Notifications may contain user-facing text or URLs. Keep only the
        // stable type identifier in diagnostics; traffic content and node
        // details must never be written to the device log.
        guard let notification else { return }
        PacketTunnelLog.logger.notice(
            "Libbox notification type=\(notification.typeName, privacy: .public) id=\(notification.typeID, privacy: .public)"
        )
    }

    // The command server expects a handler even though Aster does not expose
    // a user-facing Clash/API control plane. Keep these callbacks local to the
    // extension and do not open any external listener.
    func serviceReload() throws {}
    func serviceStop() throws {}
    func connectSSHAgent(_ ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw PacketTunnelPlatformError.unsupportedPlatformFeature
    }
    func triggerNativeCrash() throws {
        throw PacketTunnelPlatformError.unsupportedPlatformFeature
    }
    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus {
        LibboxSystemProxyStatus()
    }
    func setSystemProxyEnabled(_ enabled: Bool) throws {}
    func writeDebugMessage(_ message: String?) {
        // Libbox routes its debug stream through this callback. Do not emit
        // the raw message: it can include destinations, URLs or credentials.
        // Preserve only a coarse category so a real-device failure can be
        // distinguished between DNS, dial, TLS and routing layers.
        guard let message, !message.isEmpty else { return }
        let lowercased = message.lowercased()
        let category: String
        if lowercased.contains("dns") {
            category = "dns"
        } else if lowercased.contains("tls") || lowercased.contains("handshake") {
            category = "tls"
        } else if lowercased.contains("dial") || lowercased.contains("connect") {
            category = "dial"
        } else if lowercased.contains("route") || lowercased.contains("tun") {
            category = "route"
        } else if lowercased.contains("error") || lowercased.contains("fail") {
            category = "error"
        } else {
            category = "other"
        }
        PacketTunnelLog.logger.notice(
            "Libbox diagnostic category=\(category, privacy: .public) length=\(message.count, privacy: .public)"
        )
    }

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
        let listenerBox = UncheckedSendableBox(listener)
        monitor.pathUpdateHandler = { path in
            let shouldSignal = deliveredFirstUpdate.withValue { delivered in
                guard !delivered else { return false }
                delivered = true
                return true
            }
            if shouldSignal {
                // Release the synchronous Libbox bridge before entering the
                // callback into Go. The callback may synchronously query the
                // platform again; signalling first prevents a re-entrancy
                // deadlock while startDefaultInterfaceMonitor is waiting.
                firstUpdate.signal()
            }
            Self.publish(path, to: listenerBox.value)
        }
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
        endpointAddresses = []
    }

    private func makeNetworkSettings(
        from options: LibboxTunOptionsProtocol
    ) throws -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: options.getMTU())
        // Resolve once for both address families. Apart from avoiding duplicate
        // DNS work, this keeps IPv4/IPv6 exclusions from being built from two
        // different resolver snapshots while the interface is coming up.
        let endpointRoutes = resolvedEndpointRoutes()

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
                var excludedRoutes = Self.ipv4Routes(
                    from: options.getInet4RouteExcludeAddress(),
                    defaultsWhenEmpty: false
                )
                excludedRoutes.append(contentsOf: endpointRoutes.ipv4.map {
                    NEIPv4Route(destinationAddress: $0, subnetMask: "255.255.255.255")
                })
                ipv4.excludedRoutes = excludedRoutes
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
                var excludedRoutes = Self.ipv6Routes(
                    from: options.getInet6RouteExcludeAddress(),
                    defaultsWhenEmpty: false
                )
                excludedRoutes.append(contentsOf: endpointRoutes.ipv6.map {
                    NEIPv6Route(destinationAddress: $0, networkPrefixLength: NSNumber(value: 128))
                })
                ipv6.excludedRoutes = excludedRoutes
                settings.ipv6Settings = ipv6
            }
        }

        guard settings.ipv4Settings != nil || settings.ipv6Settings != nil else {
            throw PacketTunnelPlatformError.missingTunnelAddress
        }
        return settings
    }

    private func resolvedEndpointRoutes() -> (ipv4: [String], ipv6: [String]) {
        guard !endpointAddresses.isEmpty else {
            return ([], [])
        }
        var ipv4 = Set<String>()
        var ipv6 = Set<String>()
        for endpointAddress in endpointAddresses {
            var hints = addrinfo(
                ai_flags: AI_NUMERICHOST,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: IPPROTO_TCP,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )
            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(endpointAddress, nil, &hints, &result)
            guard status == 0, let result else {
                PacketTunnelLog.logger.error("Pre-resolved proxy endpoint was not numeric")
                continue
            }
            defer { freeaddrinfo(result) }

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
        }

        PacketTunnelLog.logger.notice(
            "Proxy endpoint route exclusions resolved: ipv4=\(ipv4.count, privacy: .public) ipv6=\(ipv6.count, privacy: .public)"
        )
        return (ipv4.sorted(), ipv6.sorted())
    }

    private func apply(_ settings: NEPacketTunnelNetworkSettings?) throws {
        PacketTunnelLog.logger.notice("Applying tunnel network settings")
        // Libbox calls openTun synchronously from a Go runtime thread. Calling
        // NetworkExtension's completion-handler API directly on that stack can
        // deadlock the provider queue: iOS waits for the provider request to
        // finish while the Go bridge waits for this callback. Hop to a detached
        // Swift task and await the imported async variant instead. This mirrors
        // Apple's continuation semantics and keeps the cgo stack re-entrant.
        let provider = UncheckedSendableBox(tunnel)
        try runBlocking {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                provider.value.setTunnelNetworkSettings(settings) { error in
                    if let error {
                        let nsError = error as NSError
                        PacketTunnelLog.logger.error(
                            "Tunnel network settings callback error domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
                        )
                        continuation.resume(throwing: error)
                    } else {
                        PacketTunnelLog.logger.notice("Tunnel network settings callback succeeded")
                        continuation.resume()
                    }
                }
            }
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

private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Bridges Libbox's synchronous platform callbacks to Swift async APIs without
/// blocking the Go runtime's callback queue. The detached task is intentional:
/// a structured task created on the caller's executor can inherit the same
/// cooperative thread that NetworkExtension needs to deliver its completion.
private func runBlocking<T>(
    _ operation: @escaping @Sendable () async throws -> T
) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let result = LockedBox<Result<T, Error>?>(nil)
    Task.detached {
        do {
            let value = try await operation()
            result.withValue { $0 = .success(value) }
        } catch {
            result.withValue { $0 = .failure(error) }
        }
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 15) == .success else {
        throw PacketTunnelPlatformError.networkSettingsTimedOut
    }
    guard let value = result.value else {
        throw PacketTunnelPlatformError.networkSettingsTimedOut
    }
    return try value.get()
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
