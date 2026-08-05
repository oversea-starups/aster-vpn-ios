import Foundation

struct TunnelConfiguration: Equatable, Sendable {
    static let schemaVersion = 1

    let node: VPNNode
    let ownerUserIdentifier: String
    let credentialReference: String

    init(
        node: VPNNode,
        ownerUserIdentifier: String,
        credentialReference: String = UUID().uuidString
    ) {
        self.node = node
        self.ownerUserIdentifier = ownerUserIdentifier
        self.credentialReference = credentialReference
    }

    var serverAddress: String {
        node.serverAddress
    }

    var nodeIdentifier: String {
        node.id
    }

    var providerConfiguration: [String: Any] {
        let configuration: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "serverAddress": serverAddress,
            "nodeIdentifier": nodeIdentifier,
            "ownerUserIdentifier": ownerUserIdentifier,
            "credentialReference": credentialReference,
        ]
        return configuration
    }

    var credentialRecord: TunnelCredentialRecord? {
        guard let nodeData = try? JSONEncoder().encode(node) else {
            return nil
        }
        return TunnelCredentialRecord(
            ownerUserIdentifier: ownerUserIdentifier,
            nodeIdentifier: nodeIdentifier,
            serverAddress: serverAddress,
            nodeData: nodeData
        )
    }

    var isValid: Bool {
        node.configurationIssue == nil
            && !ownerUserIdentifier.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && !credentialReference.isEmpty
            && credentialRecord != nil
    }
}
