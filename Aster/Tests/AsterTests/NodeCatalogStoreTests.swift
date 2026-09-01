import XCTest
@testable import Aster

@MainActor
final class NodeCatalogStoreTests: XCTestCase {
    func testRefreshInstallsMultipleNodesAndReconcilesExistingConnection() async throws {
        let current = makeConfiguration(nodeID: "legacy-node", host: "us.example.com")
        let subscription = """
        vless://550e8400-e29b-41d4-a716-446655440000@us.example.com:443?encryption=none&security=tls&type=tcp&sni=us.example.com#United%20States
        vless://550e8400-e29b-41d4-a716-446655440000@uk.example.com:443?encryption=none&security=tls&type=tcp&sni=uk.example.com#United%20Kingdom
        """
        let persistence = MemoryNodeCatalogPersistence()
        var savedConfiguration: TunnelConfiguration?
        let store = NodeCatalogStore(
            subscriptionURL: URL(string: "https://locations.astervpn.com/token")!,
            fetcher: StubNodeSubscriptionFetcher(result: .success(Data(subscription.utf8))),
            persistence: persistence,
            now: { Date(timeIntervalSince1970: 1_000) },
            loadSelectedConfiguration: { current },
            saveSelectedConfiguration: { savedConfiguration = $0 }
        )

        await store.refresh()

        XCTAssertEqual(store.nodes.count, 2)
        XCTAssertEqual(store.selectedNode?.displayName, "United States")
        XCTAssertEqual(savedConfiguration?.serverAddress, "us.example.com")
        XCTAssertNotEqual(savedConfiguration?.nodeID, "legacy-node")
        XCTAssertEqual(persistence.snapshot?.nodes.count, 2)
    }

    func testFailedRefreshKeepsLastKnownGoodCatalogAndSelection() async throws {
        let configuration = makeConfiguration(nodeID: "saved-node", host: "saved.example.com")
        let node = try VPNNode(
            id: configuration.nodeID,
            displayName: "Saved Location",
            configuration: configuration
        ).validated()
        let persistence = MemoryNodeCatalogPersistence(
            snapshot: NodeCatalogSnapshot(
                updatedAt: Date(timeIntervalSince1970: 500),
                nodes: [node]
            )
        )
        let store = NodeCatalogStore(
            subscriptionURL: URL(string: "https://locations.astervpn.com/token")!,
            fetcher: StubNodeSubscriptionFetcher(result: .failure(TestFailure.offline)),
            persistence: persistence,
            now: { Date(timeIntervalSince1970: 1_000) },
            loadSelectedConfiguration: { configuration },
            saveSelectedConfiguration: { _ in }
        )

        await store.refresh()

        XCTAssertEqual(store.nodes, [node])
        XCTAssertEqual(store.selectedNodeID, node.id)
        XCTAssertEqual(persistence.snapshot?.nodes, [node])
        XCTAssertEqual(
            store.userMessage,
            "The latest location update couldn't be verified. Your saved locations are still available."
        )
    }

    func testSelectingLocationAtomicallyUpdatesTunnelConfiguration() throws {
        let first = makeNode(id: "first", name: "United States", host: "us.example.com")
        let second = makeNode(id: "second", name: "Germany", host: "de.example.com")
        let persistence = MemoryNodeCatalogPersistence(
            snapshot: NodeCatalogSnapshot(updatedAt: Date(), nodes: [first, second])
        )
        var savedConfiguration: TunnelConfiguration?
        let store = NodeCatalogStore(
            subscriptionURL: nil,
            fetcher: StubNodeSubscriptionFetcher(result: .failure(TestFailure.offline)),
            persistence: persistence,
            loadSelectedConfiguration: { first.configuration },
            saveSelectedConfiguration: { savedConfiguration = $0 }
        )

        XCTAssertTrue(store.select(second))
        XCTAssertEqual(store.selectedNodeID, second.id)
        XCTAssertEqual(savedConfiguration, second.configuration)
    }

    func testFutureCatalogTimestampTriggersDefensiveRefresh() async {
        let cached = makeNode(id: "cached", name: "Cached", host: "cached.example.com")
        let subscription = "vless://550e8400-e29b-41d4-a716-446655440000@fresh.example.com:443?encryption=none&security=tls&type=tcp&sni=fresh.example.com#Fresh"
        let fetcher = CountingNodeSubscriptionFetcher(data: Data(subscription.utf8))
        let store = NodeCatalogStore(
            subscriptionURL: URL(string: "https://locations.astervpn.com/token")!,
            fetcher: fetcher,
            persistence: MemoryNodeCatalogPersistence(
                snapshot: NodeCatalogSnapshot(
                    updatedAt: Date(timeIntervalSince1970: 2_000),
                    nodes: [cached]
                )
            ),
            now: { Date(timeIntervalSince1970: 1_000) },
            loadSelectedConfiguration: { cached.configuration },
            saveSelectedConfiguration: { _ in }
        )

        await store.refreshIfNeeded()

        let fetchCount = await fetcher.fetchCount
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(store.nodes.first?.displayName, "Available location")
    }

    func testRecentCatalogSkipsAutomaticRefresh() async {
        let cached = makeNode(id: "cached", name: "Cached", host: "cached.example.com")
        let fetcher = CountingNodeSubscriptionFetcher(data: Data("unused".utf8))
        let store = NodeCatalogStore(
            subscriptionURL: URL(string: "https://locations.astervpn.com/token")!,
            fetcher: fetcher,
            persistence: MemoryNodeCatalogPersistence(
                snapshot: NodeCatalogSnapshot(
                    updatedAt: Date(timeIntervalSince1970: 900),
                    nodes: [cached]
                )
            ),
            now: { Date(timeIntervalSince1970: 1_000) },
            loadSelectedConfiguration: { cached.configuration },
            saveSelectedConfiguration: { _ in }
        )

        await store.refreshIfNeeded()

        let fetchCount = await fetcher.fetchCount
        XCTAssertEqual(fetchCount, 0)
        XCTAssertEqual(store.nodes, [cached])
        XCTAssertEqual(store.selectedNodeID, cached.id)
    }

    func testFailedConfigurationWriteKeepsPreviousSelection() throws {
        let first = makeNode(id: "first", name: "United States", host: "us.example.com")
        let second = makeNode(id: "second", name: "Germany", host: "de.example.com")
        let store = NodeCatalogStore(
            subscriptionURL: nil,
            fetcher: StubNodeSubscriptionFetcher(result: .failure(TestFailure.offline)),
            persistence: MemoryNodeCatalogPersistence(
                snapshot: NodeCatalogSnapshot(updatedAt: Date(), nodes: [first, second])
            ),
            loadSelectedConfiguration: { first.configuration },
            saveSelectedConfiguration: { _ in throw TestFailure.storage }
        )

        XCTAssertFalse(store.select(second))
        XCTAssertEqual(store.selectedNodeID, first.id)
        XCTAssertEqual(store.selectedNode, first)
        XCTAssertEqual(
            store.userMessage,
            "Aster couldn't save this VPN location. Please try another one."
        )
    }

    func testPublicSubscriptionURLValidationRejectsLocalAndPlaceholderHosts() {
        XCTAssertNotNil(AppConfiguration.validatedPublicHTTPSURL("https://locations.astervpn.com/token"))
        XCTAssertNil(AppConfiguration.validatedPublicHTTPSURL("http://locations.astervpn.com/token"))
        XCTAssertNil(AppConfiguration.validatedPublicHTTPSURL("https://localhost/token"))
        XCTAssertNil(AppConfiguration.validatedPublicHTTPSURL("https://192.168.1.2/token"))
        XCTAssertNil(AppConfiguration.validatedPublicHTTPSURL("https://aster.example/token"))
        XCTAssertNil(AppConfiguration.validatedPublicHTTPSURL("https://user:secret@locations.astervpn.com/token"))
    }

    func testCachedStatusRecordsAreRemovedBeforePresentation() {
        let status = makeNode(id: "status", name: "剩余流量：1 GB", host: "status.example.com")
        let location = makeNode(id: "location", name: "US-01｜VIP🇺🇸", host: "us.example.com")
        let persistence = MemoryNodeCatalogPersistence(
            snapshot: NodeCatalogSnapshot(updatedAt: Date(), nodes: [status, location])
        )

        let store = NodeCatalogStore(
            subscriptionURL: nil,
            fetcher: StubNodeSubscriptionFetcher(result: .failure(TestFailure.offline)),
            persistence: persistence,
            loadSelectedConfiguration: { location.configuration },
            saveSelectedConfiguration: { _ in }
        )

        XCTAssertEqual(store.nodes, [location])
        XCTAssertEqual(store.selectedNodeID, location.id)
        XCTAssertEqual(persistence.snapshot?.nodes, [location])
    }

    func testFilePersistenceRecoversPreviousCatalogAfterPrimaryCorruption() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AsterCatalogTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = FileNodeCatalogPersistence(directoryURL: directory)
        let first = NodeCatalogSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            nodes: [makeNode(id: "first", name: "United States", host: "us.example.com")]
        )
        let second = NodeCatalogSnapshot(
            updatedAt: Date(timeIntervalSince1970: 200),
            nodes: [makeNode(id: "second", name: "Japan", host: "jp.example.com")]
        )

        try persistence.save(first)
        try persistence.save(second)
        try Data("corrupt".utf8).write(
            to: directory.appendingPathComponent("node_catalog.json"),
            options: [.atomic]
        )

        XCTAssertEqual(try persistence.load(), first)
    }

    func testCatalogLoadFailureIsVisibleAndKeepsCurrentConfiguration() {
        let configuration = makeConfiguration(nodeID: "current", host: "current.example.com")
        let store = NodeCatalogStore(
            subscriptionURL: nil,
            fetcher: StubNodeSubscriptionFetcher(result: .failure(TestFailure.offline)),
            persistence: ThrowingNodeCatalogPersistence(),
            loadSelectedConfiguration: { configuration },
            saveSelectedConfiguration: { _ in }
        )

        XCTAssertEqual(store.selectedNode?.displayName, "Current Location")
        XCTAssertEqual(store.selectedNodeID, configuration.nodeID)
        XCTAssertEqual(
            store.userMessage,
            "Saved locations need repair. Your current location will be kept if available."
        )
    }

    private func makeNode(id: String, name: String, host: String) -> VPNNode {
        VPNNode(id: id, displayName: name, configuration: makeConfiguration(nodeID: id, host: host))
    }

    private func makeConfiguration(nodeID: String, host: String) -> TunnelConfiguration {
        TunnelConfiguration(
            nodeID: nodeID,
            serverAddress: host,
            serverPort: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            tlsEnabled: true,
            serverName: host
        )
    }
}

private final class MemoryNodeCatalogPersistence: NodeCatalogPersisting {
    var snapshot: NodeCatalogSnapshot?

    init(snapshot: NodeCatalogSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() throws -> NodeCatalogSnapshot? { snapshot }

    func save(_ snapshot: NodeCatalogSnapshot) throws {
        self.snapshot = snapshot
    }
}

private struct ThrowingNodeCatalogPersistence: NodeCatalogPersisting {
    func load() throws -> NodeCatalogSnapshot? { throw TestFailure.storage }

    func save(_ snapshot: NodeCatalogSnapshot) throws {
        throw TestFailure.storage
    }
}

private struct StubNodeSubscriptionFetcher: NodeSubscriptionFetching, @unchecked Sendable {
    let result: Result<Data, Error>

    func fetch(from url: URL) async throws -> Data {
        try result.get()
    }
}

private actor CountingNodeSubscriptionFetcher: NodeSubscriptionFetching {
    private(set) var fetchCount = 0
    let data: Data

    init(data: Data) {
        self.data = data
    }

    func fetch(from url: URL) async throws -> Data {
        fetchCount += 1
        return data
    }
}

private enum TestFailure: Error {
    case offline
    case storage
}
