import Foundation
import Network

protocol NodeReachabilityChecking: Sendable {
    func reachableNodeIDs(for nodes: [VPNNode]) async -> Set<String>
}

/// Performs a short, content-free endpoint preflight against each bundled node.
///
/// This is intentionally only a first gate: protocol authentication and
/// Internet egress are verified when a node is selected and the packet tunnel
/// runs its HTTPS data-plane probe. TLS-enabled lines must at least complete a
/// TLS handshake (certificate trust is not evaluated here because Reality
/// lines intentionally use a non-public certificate); plaintext lines only
/// need a TCP connection. A node whose endpoint is not even reachable should
/// not clutter the Locations UI, though.
struct NodeEndpointReachabilityChecker: NodeReachabilityChecking {
    private let timeout: TimeInterval
    private let batchSize: Int

    init(timeout: TimeInterval = 3, batchSize: Int = 8) {
        self.timeout = timeout
        self.batchSize = max(1, batchSize)
    }

    func reachableNodeIDs(for nodes: [VPNNode]) async -> Set<String> {
        var reachable = Set<String>()
        guard !nodes.isEmpty else { return reachable }

        for start in stride(from: 0, to: nodes.count, by: batchSize) {
            let end = min(start + batchSize, nodes.count)
            let batch = Array(nodes[start..<end])
            let results = await withTaskGroup(of: (String, Bool).self, returning: [(String, Bool)].self) { group in
                for node in batch {
                    group.addTask {
                        (node.id, await self.isReachable(node.configuration))
                    }
                }

                var values: [(String, Bool)] = []
                for await value in group {
                    values.append(value)
                }
                return values
            }
            for (id, isReachable) in results where isReachable {
                reachable.insert(id)
            }
        }
        return reachable
    }

    private func isReachable(_ configuration: TunnelConfiguration) async -> Bool {
        guard let port = NWEndpoint.Port(rawValue: UInt16(configuration.serverPort)) else {
            return false
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(configuration.serverAddress),
            port: port,
            using: parameters(for: configuration)
        )
        let deadline = DispatchTime.now() + timeout

        return await withCheckedContinuation { continuation in
            let completion = ReachabilityCompletion(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    completion.finish(true)
                case .failed, .cancelled:
                    completion.finish(false)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
                completion.finish(false)
            }
        }
    }

    private func parameters(for configuration: TunnelConfiguration) -> NWParameters {
        guard configuration.tlsEnabled else { return .tcp }

        let tlsOptions = NWProtocolTLS.Options()
        if let serverName = configuration.serverName {
            sec_protocol_options_set_tls_server_name(
                tlsOptions.securityProtocolOptions,
                serverName
            )
        }

        // Endpoint preflight is not a trust decision. The actual tunnel uses
        // Libbox's protocol-specific TLS/Reality settings; accepting the
        // certificate here lets us test the server hello without weakening the
        // data plane.
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, complete in complete(true) },
            DispatchQueue.global(qos: .utility)
        )
        return NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
    }
}

private final class ReachabilityCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Bool, Never>?
    private var completed = false

    init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Bool) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        connection.cancel()
        continuation?.resume(returning: result)
    }
}
