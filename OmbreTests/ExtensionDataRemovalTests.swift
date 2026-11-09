import Foundation
@testable import Ombre
import Testing
import WebKit

/// Removing an extension removes what WebKit kept for it.
@MainActor
struct ExtensionDataRemovalTests {
    @Test func theFolderIsOnlyTheExtensionsOwn() {
        let library = URL(fileURLWithPath: "/Library-test")
        let store = UUID()
        let id = UUID().uuidString
        let folder = ExtensionDataFolder.url(library: library, store: store, extensionID: id)
        #expect(folder?.path == "/Library-test/WebKit/WebExtensions/\(store.uuidString)/\(id)")
        #expect(ExtensionDataFolder.url(library: library, store: store, extensionID: "") == nil)
        #expect(ExtensionDataFolder.url(library: library, store: store, extensionID: "../Other") == nil)
        #expect(ExtensionDataFolder.url(library: library, store: store, extensionID: "\(id)/..") == nil)
    }

    /// WebKit's `removeData` used to leave the folder (uBlock's: 120 MB).
    @available(macOS 15.4, *)
    @Test func aRemovedExtensionLeavesNoFolder() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let manifest = """
        {"manifest_version": 3, "name": "Data test", "version": "1.0", "permissions": ["storage"],
         "background": {"service_worker": "background.js"}}
        """
        try Data(manifest.utf8).write(to: source.appendingPathComponent("manifest.json"))
        try Data("chrome.storage.local.set({ kept: true });".utf8)
            .write(to: source.appendingPathComponent("background.js"))

        let store = UUID()
        let controller = WKWebExtensionController(configuration: .init(identifier: store))
        let library = try #require(ExtensionDataFolder.library)
        let storeFolder = library.appendingPathComponent("WebKit/WebExtensions/\(store.uuidString)")
        defer { try? FileManager.default.removeItem(at: storeFolder) }

        let context = try await WKWebExtensionContext(for: WKWebExtension(resourceBaseURL: source))
        let id = UUID().uuidString
        context.uniqueIdentifier = id
        try controller.load(context)
        let folder = try #require(ExtensionDataFolder.url(library: library, store: store, extensionID: id))
        for _ in 0 ..< 100 where !FileManager.default.fileExists(atPath: folder.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(FileManager.default.fileExists(atPath: folder.path))

        try controller.unload(context)
        await ExtensionDataFolder.removeAll(of: id, from: controller)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        // Not written again once WebKit lets go of the extension.
        try await Task.sleep(for: .milliseconds(500))
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
