import AppKit
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

struct ExtensionSiteAccessTests {
    private func record(otherSites: SiteDecision = .ask) -> ExtensionRecord {
        var record = ExtensionRecord(
            source: .safariApp(appexPath: "/x.appex", bundleIdentifier: "x"),
            name: "X",
            appName: nil
        )
        record.grantedMatchPatterns = ["*://*/*"]
        record.otherSites = otherSites
        return record
    }

    @Test func aWebsiteIsAnHttpHost() {
        #expect(ExtensionSiteAccess.host(of: URL(string: "https://Mail.Example.com/inbox")) == "mail.example.com")
        #expect(ExtensionSiteAccess.host(of: URL(string: "file:///tmp/a.html")) == nil)
        #expect(ExtensionSiteAccess.pattern(forHost: "example.com") == "*://example.com/*")
    }

    @Test func aWebsiteRuleWinsOverOtherWebsites() {
        var record = record()
        record.siteRules = ExtensionSiteAccess.setting(.allow, for: "a.com", in: [])
        record.siteRules = ExtensionSiteAccess.setting(.deny, for: "b.com", in: record.siteRules)
        #expect(ExtensionSiteAccess.decision(for: "a.com", in: record) == .allow)
        #expect(ExtensionSiteAccess.decision(for: "b.com", in: record) == .deny)
        #expect(ExtensionSiteAccess.decision(for: "c.com", in: record) == .ask)
        // "Ask" forgets the website.
        record.siteRules = ExtensionSiteAccess.setting(.ask, for: "a.com", in: record.siteRules)
        #expect(record.siteRules.map(\.host) == ["b.com"])
    }

    @Test func oneDayEnds() {
        let now = Date()
        var record = record()
        record.siteRules = ExtensionSiteAccess.setting(
            .allow, for: "a.com", until: now.addingTimeInterval(60), in: []
        )
        #expect(ExtensionSiteAccess.decision(for: "a.com", in: record, at: now) == .allow)
        #expect(ExtensionSiteAccess.decision(for: "a.com", in: record, at: now.addingTimeInterval(120)) == .ask)
    }

    @Test func allWebsitesAreGrantedOnlyWhenAllowed() {
        var record = record(otherSites: .ask)
        record.siteRules = ExtensionSiteAccess.setting(.allow, for: "a.com", in: [])
        record.siteRules = ExtensionSiteAccess.setting(.deny, for: "b.com", in: record.siteRules)
        #expect(ExtensionSiteAccess.grantedPatterns(for: record).map(\.pattern) == ["*://a.com/*"])
        #expect(ExtensionSiteAccess.deniedPatterns(for: record) == ["*://b.com/*"])

        record.otherSites = .allow
        #expect(ExtensionSiteAccess.grantedPatterns(for: record).map(\.pattern) == ["*://*/*", "*://a.com/*"])
    }

    @Test func extensionsAddedBeforeKeepAllTheirWebsites() throws {
        let json = """
        [{"id":"1","source":{"safariApp":{"appexPath":"/x.appex","bundleIdentifier":"x"}},"name":"X",
          "isEnabled":true,"grantedPermissions":[],"grantedMatchPatterns":["*://*/*"],
          "installedAt":"2026-10-30T10:00:00Z"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try #require(try decoder.decode([ExtensionRecord].self, from: Data(json.utf8)).first)
        #expect(record.otherSites == .allow)
        #expect(record.isPinned)
        #expect(record.siteRules.isEmpty)
    }

    @Test func unpinnedExtensionsKeepTheMenu() {
        #expect(ExtensionStripLayout.visibleCount(items: 2, capacity: 5, hasMenu: true) == 2)
        #expect(ExtensionStripLayout.visibleCount(items: 3, capacity: 3, hasMenu: true) == 2)
        #expect(ExtensionStripLayout.visibleCount(items: 1, capacity: 1, hasMenu: true) == 0)
    }

    @Test func shortcutsReadLikeMenus() {
        #expect(ShortcutText.text(key: "y", modifiers: [.command, .shift]) == "⇧⌘Y")
        #expect(ShortcutText.text(key: "l", modifiers: [.control, .option]) == "⌃⌥L")
    }
}
