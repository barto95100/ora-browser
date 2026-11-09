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
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
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
