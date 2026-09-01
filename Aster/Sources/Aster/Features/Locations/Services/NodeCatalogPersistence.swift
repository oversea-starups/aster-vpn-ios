import Foundation

protocol NodeCatalogPersisting {
    func load() throws -> NodeCatalogSnapshot?
    func save(_ snapshot: NodeCatalogSnapshot) throws
}

struct FileNodeCatalogPersistence: NodeCatalogPersisting {
    private let fileManager: FileManager
    private let appGroupIdentifier: String
    private let directoryURL: URL?

    init(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = AppConstants.appGroupName,
        directoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.appGroupIdentifier = appGroupIdentifier
        self.directoryURL = directoryURL
    }

    func load() throws -> NodeCatalogSnapshot? {
        let url = try catalogURL()
        let backup = backupURL(for: url)
        guard fileManager.fileExists(atPath: url.path) else {
            return try loadBackupIfAvailable(at: backup)
        }
        do {
            return try loadSnapshot(at: url)
        } catch let error as VPNNodeError {
            if let restored = try loadBackupIfAvailable(at: backup) {
                return restored
            }
            throw error
        } catch {
            if let restored = try loadBackupIfAvailable(at: backup) {
                return restored
            }
            throw NodeCatalogPersistenceError.corruptCatalog
        }
    }

    func save(_ snapshot: NodeCatalogSnapshot) throws {
        let validated = try snapshot.validated()
        let data = try JSONEncoder().encode(validated)
        let url = try catalogURL()
        if fileManager.fileExists(atPath: url.path),
           (try? loadSnapshot(at: url)) != nil,
           let existingData = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
            // Keep the previous bytes separately so an interrupted or corrupt
            // primary write can recover a validated last-known-good catalog. Do
            // not replace a healthy backup with bytes from a corrupt primary.
            try existingData.write(
                to: backupURL(for: url),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func catalogURL() throws -> URL {
        if let directoryURL {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            return directoryURL.appendingPathComponent("node_catalog.json", isDirectory: false)
        }
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw NodeCatalogPersistenceError.appGroupUnavailable
        }
        return container.appendingPathComponent("node_catalog.json", isDirectory: false)
    }

    private func backupURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("bak.json")
    }

    private func loadBackupIfAvailable(at url: URL) throws -> NodeCatalogSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try loadSnapshot(at: url)
        } catch {
            throw NodeCatalogPersistenceError.corruptCatalog
        }
    }

    private func loadSnapshot(at url: URL) throws -> NodeCatalogSnapshot {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try JSONDecoder().decode(NodeCatalogSnapshot.self, from: data).validated()
    }
}

enum NodeCatalogPersistenceError: Error, LocalizedError, Equatable {
    case appGroupUnavailable
    case corruptCatalog

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "VPN location storage isn't available."
        case .corruptCatalog:
            return "The saved VPN location list couldn't be verified."
        }
    }
}
