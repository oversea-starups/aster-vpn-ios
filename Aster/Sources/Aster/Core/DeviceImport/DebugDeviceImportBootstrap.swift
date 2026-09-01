#if ASTER_DEVICE_IMPORT
import Foundation
import OSLog

/// One-shot device QA bridge for transferring a validated catalog when the
/// CoreDevice App Group file service cannot create a file at the container root.
/// The compile flag is supplied only to the temporary Debug device build.
enum DebugDeviceImportBootstrap {
    private static let logger = Logger(subsystem: "com.astervpn.Aster", category: "DeviceImport")
    private static let catalogFileName = "node_catalog.json"
    private static let configurationFileName = "tunnel_config.json"

    static func installIfPresent() {
        let fileManager = FileManager.default
        guard
            let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first,
            let groupURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: AppConstants.appGroupName
            )
        else {
            return
        }

        let stagedCatalogURL = libraryURL.appendingPathComponent(catalogFileName, isDirectory: false)
        let stagedConfigurationURL = libraryURL.appendingPathComponent(configurationFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: stagedCatalogURL.path) ||
                fileManager.fileExists(atPath: stagedConfigurationURL.path) else {
            return
        }

        do {
            let catalog = try stagedCatalog(fileManager: fileManager, url: stagedCatalogURL)
            let configuration = try stagedConfiguration(fileManager: fileManager, url: stagedConfigurationURL)

            if let catalog {
                let destination = groupURL.appendingPathComponent(catalogFileName, isDirectory: false)
                let data = try JSONEncoder().encode(catalog)
                try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            if let configuration {
                let destination = groupURL.appendingPathComponent(configurationFileName, isDirectory: false)
                let data = try JSONEncoder().encode(configuration)
                try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }

            if fileManager.fileExists(atPath: stagedCatalogURL.path) {
                try fileManager.removeItem(at: stagedCatalogURL)
            }
            if fileManager.fileExists(atPath: stagedConfigurationURL.path) {
                try fileManager.removeItem(at: stagedConfigurationURL)
            }
        } catch {
            logger.error("Device location import failed validation or storage")
        }
    }

    private static func stagedCatalog(
        fileManager: FileManager,
        url: URL
    ) throws -> NodeCatalogSnapshot? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try JSONDecoder().decode(NodeCatalogSnapshot.self, from: data).validated()
    }

    private static func stagedConfiguration(
        fileManager: FileManager,
        url: URL
    ) throws -> TunnelConfiguration? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try JSONDecoder().decode(TunnelConfiguration.self, from: data).validated()
    }
}
#endif
