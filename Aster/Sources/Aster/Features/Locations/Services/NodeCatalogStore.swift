import Foundation

@MainActor
final class NodeCatalogStore: ObservableObject {
    static let shared = NodeCatalogStore()

    @Published private(set) var nodes: [VPNNode] = []
    @Published private(set) var selectedNodeID: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var userMessage: String?
    @Published private(set) var lastDiscardedEntryCount = 0

    private let subscriptionURL: URL?
    private let fetcher: any NodeSubscriptionFetching
    private let parser: NodeSubscriptionParser
    private let persistence: any NodeCatalogPersisting
    private let now: () -> Date
    private let loadSelectedConfiguration: () throws -> TunnelConfiguration
    private let saveSelectedConfiguration: (TunnelConfiguration) throws -> Void
    private let refreshInterval: TimeInterval
    private var restoreMessage: String? = nil

    init(
        subscriptionURL: URL? = AppConfiguration.nodeSubscriptionURL,
        fetcher: any NodeSubscriptionFetching = URLSessionNodeSubscriptionClient(),
        parser: NodeSubscriptionParser = NodeSubscriptionParser(),
        persistence: any NodeCatalogPersisting = FileNodeCatalogPersistence(),
        now: @escaping () -> Date = Date.init,
        refreshInterval: TimeInterval = 6 * 60 * 60,
        loadSelectedConfiguration: @escaping () throws -> TunnelConfiguration = TunnelConfigManager.loadConfig,
        saveSelectedConfiguration: @escaping (TunnelConfiguration) throws -> Void = TunnelConfigManager.saveConfig
    ) {
        self.subscriptionURL = subscriptionURL
        self.fetcher = fetcher
        self.parser = parser
        self.persistence = persistence
        self.now = now
        self.refreshInterval = refreshInterval
        self.loadSelectedConfiguration = loadSelectedConfiguration
        self.saveSelectedConfiguration = saveSelectedConfiguration
        restoreLastKnownGoodCatalog()
    }

    var selectedNode: VPNNode? {
        guard let selectedNodeID else { return nil }
        return nodes.first(where: { $0.id == selectedNodeID })
    }

    var hasUpdateSource: Bool {
        subscriptionURL != nil
    }

    func refreshIfNeeded() async {
        if let lastUpdated {
            let age = now().timeIntervalSince(lastUpdated)
            if age >= 0, age < refreshInterval {
                return
            }
        }
        await refresh(force: false)
    }

    func refresh(force: Bool = true) async {
        guard !isRefreshing else { return }
        guard let subscriptionURL else {
            if nodes.isEmpty {
                userMessage = "VPN locations are temporarily unavailable. Please try again later."
            }
            return
        }
        let currentTime = now()
        if !force,
           let lastUpdated,
           currentTime.timeIntervalSince(lastUpdated) >= 0,
           currentTime.timeIntervalSince(lastUpdated) < refreshInterval {
                return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let data = try await fetcher.fetch(from: subscriptionURL)
            let result = try parser.parse(data)
            try install(result)
            userMessage = nil
        } catch {
            userMessage = nodes.isEmpty
                ? "Aster couldn't load VPN locations. Check your connection and try again."
                : "The latest location update couldn't be verified. Your saved locations are still available."
        }
    }

    @discardableResult
    func select(_ node: VPNNode) -> Bool {
        guard nodes.contains(where: { $0.id == node.id }) else { return false }
        do {
            let validated = try node.validated()
            try saveSelectedConfiguration(validated.configuration)
            selectedNodeID = validated.id
            userMessage = nil
            return true
        } catch {
            userMessage = "Aster couldn't save this VPN location. Please try another one."
            return false
        }
    }

    func clearMessage() {
        userMessage = nil
    }

    private func restoreLastKnownGoodCatalog() {
        var restoredCatalog = false
        do {
            if let snapshot = try persistence.load() {
                restoredCatalog = true
                let realLocations = snapshot.nodes.filter { !VPNNode.isStatusRecord($0.displayName) }
                if !realLocations.isEmpty {
                    nodes = realLocations
                    lastUpdated = snapshot.updatedAt
                    if realLocations.count != snapshot.nodes.count {
                        let sanitized = NodeCatalogSnapshot(updatedAt: snapshot.updatedAt, nodes: realLocations)
                        do {
                            try persistence.save(sanitized)
                        } catch {
                            restoreMessage = "Saved locations were filtered, but the repaired copy couldn't be stored."
                        }
                    }
                }
            }
        } catch {
            // Do not silently turn a persistence failure into an empty list.
            // The selected tunnel configuration below remains a recoverable
            // fallback while the UI explains why the catalog needs repair.
            restoreMessage = "Saved locations need repair. Your current location will be kept if available."
        }

        if !restoredCatalog || nodes.isEmpty {
            restoreBundledCatalogIfAvailable()
        }

        let selectedConfiguration: TunnelConfiguration?
        do {
            selectedConfiguration = try loadSelectedConfiguration().validated()
        } catch {
            selectedConfiguration = nil
        }
        if let selectedConfiguration,
           let matchingNode = nodes.first(where: { $0.matchesConnection(selectedConfiguration) }) {
            selectedNodeID = matchingNode.id
        } else if let selectedConfiguration {
            let legacyNode = VPNNode(
                id: selectedConfiguration.nodeID,
                displayName: "Current Location",
                configuration: selectedConfiguration
            )
            if let validated = try? legacyNode.validated() {
                nodes.insert(validated, at: 0)
                selectedNodeID = validated.id
            }
        } else if let first = nodes.first {
            selectedNodeID = first.id
            try? saveSelectedConfiguration(first.configuration)
        }

        if let restoreMessage {
            userMessage = restoreMessage
        }
    }

    private func restoreBundledCatalogIfAvailable() {
        guard nodes.isEmpty,
              let url = Bundle.main.url(forResource: "node_catalog", withExtension: "json") else {
            return
        }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let snapshot = try JSONDecoder().decode(NodeCatalogSnapshot.self, from: data).validated()
            try persistence.save(snapshot)
            nodes = snapshot.nodes
            lastUpdated = snapshot.updatedAt
        } catch {
            restoreMessage = "The built-in VPN locations couldn't be verified."
        }
    }

    private func install(_ result: NodeSubscriptionParseResult) throws {
        let currentConfiguration = try? loadSelectedConfiguration().validated()
        var updatedNodes = result.nodes

        let selected: VPNNode
        if let currentConfiguration,
           let matching = updatedNodes.first(where: { $0.matchesConnection(currentConfiguration) }) {
            selected = matching
        } else if let selectedNodeID,
                  let matching = updatedNodes.first(where: { $0.id == selectedNodeID }) {
            selected = matching
        } else if let currentConfiguration {
            let legacyNode = try VPNNode(
                id: currentConfiguration.nodeID,
                displayName: "Current Location",
                configuration: currentConfiguration
            ).validated()
            if !updatedNodes.contains(where: { $0.id == legacyNode.id }) {
                updatedNodes.append(legacyNode)
            }
            selected = legacyNode
        } else if let first = updatedNodes.first {
            selected = first
        } else {
            throw VPNNodeError.invalidCatalog
        }

        let installedAt = now()
        let snapshot = try NodeCatalogSnapshot(updatedAt: installedAt, nodes: updatedNodes).validated()
        try persistence.save(snapshot)
        try saveSelectedConfiguration(selected.configuration)

        nodes = snapshot.nodes
        selectedNodeID = selected.id
        lastUpdated = installedAt
        lastDiscardedEntryCount = result.discardedEntryCount
    }
}
