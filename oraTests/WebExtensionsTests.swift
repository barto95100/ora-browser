import Foundation
@testable import Ora
import Testing

struct WebExtensionsTests {
    @Test func onlySafariWebExtensionsAreFound() {
        let safari: [String: Any] = ["NSExtension": ["NSExtensionPointIdentifier": "com.apple.Safari.web-extension"]]
        let contentBlocker: [String: Any] = [
            "NSExtension": ["NSExtensionPointIdentifier": "com.apple.Safari.content-blocker"]
        ]
        #expect(SafariExtensionScanner.isWebExtension(info: safari))
        #expect(!SafariExtensionScanner.isWebExtension(info: contentBlocker))
        #expect(!SafariExtensionScanner.isWebExtension(info: [:]))
    }

    @Test func extensionNamePrefersTheDisplayName() {
        #expect(SafariExtensionScanner.name(info: ["CFBundleDisplayName": "Bitwarden", "CFBundleName": "safari"])
            == "Bitwarden")
        #expect(SafariExtensionScanner.name(info: ["CFBundleName": "safari"]) == "safari")
        #expect(SafariExtensionScanner.name(info: ["CFBundleDisplayName": ""]) == nil)
    }

    @Test func allSitesReadAsOneLine() {
        #expect(ExtensionPermissionText.describeSites(["https://*/*", "http://*/*"]) == ["All websites"])
        #expect(ExtensionPermissionText.describeSites(["https://b.com/*", "https://a.com/*"])
            == ["https://a.com/*", "https://b.com/*"])
        #expect(ExtensionPermissionText.describe("tabs") == "See your tabs' addresses and titles")
        #expect(ExtensionPermissionText.describe("somethingNew") == "somethingNew")
    }

    @Test func registryKeepsRecordsAndSetsAsideAnUnreadableFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let registry = ExtensionRegistry(fileURL: folder.appendingPathComponent("extensions.json"))

        var record = ExtensionRecord(
            source: .safariApp(
                appexPath: "/Applications/Bitwarden.app/Contents/PlugIns/safari.appex",
                bundleIdentifier: "com.bitwarden.desktop.safari"
            ),
            name: "Bitwarden",
            appName: "Bitwarden"
        )
        record.grantedPermissions = ["storage", "tabs"]
        record.grantedMatchPatterns = ["*://*/*"]
        registry.save([record])
        let loaded = registry.load()
        #expect(loaded.map(\.id) == [record.id])
        #expect(loaded.first?.grantedPermissions == ["storage", "tabs"])
        #expect(loaded.first?.bundleIdentifier == "com.bitwarden.desktop.safari")

        try Data("not json".utf8).write(to: registry.fileURL)
        #expect(registry.load().isEmpty)
        let aside = folder.appendingPathComponent("extensions.unreadable.json")
        #expect(FileManager.default.fileExists(atPath: aside.path))
    }
}

struct ExtensionStripLayoutTests {
    @Test func allShowWhenTheyFit() {
        #expect(ExtensionStripLayout.visibleCount(items: 3, capacity: 3) == 3)
        #expect(ExtensionStripLayout.visibleCount(items: 2, capacity: 5) == 2)
    }

    @Test func theMenuTakesOneSlotWhenTheyDont() {
        #expect(ExtensionStripLayout.visibleCount(items: 5, capacity: 3) == 2)
        #expect(ExtensionStripLayout.visibleCount(items: 5, capacity: 1) == 0)
        #expect(ExtensionStripLayout.visibleCount(items: 2, capacity: 0) == 0)
        #expect(ExtensionStripLayout.visibleCount(items: 0, capacity: 0) == 0)
    }
}
