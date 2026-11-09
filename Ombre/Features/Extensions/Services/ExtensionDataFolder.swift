import Foundation
import OSLog
import WebKit

private let logger = Logger(category: "Extensions")

/// What WebKit keeps on disk for an extension: `removeData` empties its
/// storage but leaves its folder (state, registered scripts, network rules,
/// over 100 MB for a content blocker).
enum ExtensionDataFolder {
    /// `<Library>/WebKit/WebExtensions/<store>/<extension>`; nil for an
    /// identifier that isn't a UUID (never a path).
    static func url(library: URL, store: UUID, extensionID: String) -> URL? {
        guard UUID(uuidString: extensionID) != nil, !extensionID.contains("/") else { return nil }
        return library
            .appendingPathComponent("WebKit/WebExtensions", isDirectory: true)
            .appendingPathComponent(store.uuidString, isDirectory: true)
            .appendingPathComponent(extensionID, isDirectory: true)
    }

    static var library: URL? {
        StaleData.library
    }

    /// The folders of extensions no longer in the registry: removed before
    /// Ombre deleted their folder, or kept by an earlier store (a whole
    /// store goes when none of its extensions is installed). Only folders
    /// named by a UUID; an extension in the registry is always kept.
    static func orphans(in root: URL, keeping installedIDs: Set<String>, currentStore: UUID) -> [URL] {
        let kept = Set(installedIDs.map { $0.uppercased() })
        return uuidFolders(in: root).flatMap { store -> [URL] in
            let extensions = uuidFolders(in: store)
            let orphans = extensions.filter { !kept.contains($0.lastPathComponent.uppercased()) }
            let isCurrent = store.lastPathComponent.uppercased() == currentStore.uuidString.uppercased()
            if !isCurrent, orphans.count == extensions.count { return [store] }
            return orphans
        }
    }

    private static func uuidFolders(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return contents.filter { url in
            UUID(uuidString: url.lastPathComponent) != nil
                && (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Removes `orphans`, at launch; logged with the space freed.
    static func removeOrphans(keeping installedIDs: Set<String>, currentStore: UUID) {
        guard let library else { return }
        let root = library.appendingPathComponent("WebKit/WebExtensions", isDirectory: true)
        var removed: [(name: String, bytes: Int64)] = []
        for folder in orphans(in: root, keeping: installedIDs, currentStore: currentStore) {
            let bytes = StaleData.size(of: folder)
            do {
                try FileManager.default.removeItem(at: folder)
                let store = folder.deletingLastPathComponent().lastPathComponent
                let name = store == "WebExtensions" ? "store \(folder.lastPathComponent)" : folder.lastPathComponent
                removed.append((name, bytes))
            } catch {
                let reason = error.localizedDescription
                logger
                    .error("Removing \(folder.lastPathComponent, privacy: .public) failed: \(reason, privacy: .public)")
            }
        }
        StaleData.logRemovals(removed, of: "extension data")
    }

    /// All the data of an extension already unloaded: its storage through
    /// WebKit, then its folder.
    @available(macOS 15.4, *)
    @MainActor
    static func removeAll(of extensionID: String, from controller: WKWebExtensionController) async {
        let types = WKWebExtensionController.allExtensionDataTypes
        let records = await controller.dataRecords(ofTypes: types)
        let own = records.filter { $0.uniqueIdentifier == extensionID }
        if !own.isEmpty { await controller.removeData(ofTypes: types, from: own) }

        guard let library, let store = controller.configuration.identifier,
              let folder = url(library: library, store: store, extensionID: extensionID)
        else { return }
        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.removeItem(at: folder)
            } catch CocoaError.fileNoSuchFile {
                // Nothing kept.
            } catch {
                logger.error("Removing an extension's data failed: \(error.localizedDescription, privacy: .public)")
            }
        }.value
    }
}
