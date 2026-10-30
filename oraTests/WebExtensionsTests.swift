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
        #expect(!record.allowsPrivateBrowsing)
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

struct ChromeWebStoreTests {
    private let darkReader = "eimadpbcbfnmbkopoojfekhnkhdbieeh"

    @Test func storePagesGiveTheExtension() {
        let new = URL(string: "https://chromewebstore.google.com/detail/dark-reader/\(darkReader)?hl=fr")
        let old = URL(string: "https://chrome.google.com/webstore/detail/dark-reader/\(darkReader)")
        #expect(ChromeWebStore.extensionID(from: new) == darkReader)
        #expect(ChromeWebStore.extensionID(from: old) == darkReader)
        #expect(ChromeWebStore
            .extensionID(from: URL(string: "https://chromewebstore.google.com/category/extensions")) == nil)
        #expect(ChromeWebStore.extensionID(from: URL(string: "https://example.com/detail/x/\(darkReader)")) == nil)
    }

    @Test func downloadAsksForTheExtension() throws {
        let url = try #require(ChromeWebStore.downloadURL(for: darkReader))
        #expect(url.host == "clients2.google.com")
        #expect(url.absoluteString.contains("x=id%3D\(darkReader)%26uc"))
    }

    @Test func crxGivesItsZip() throws {
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 0x01, 0x02])
        func uint32(_ value: UInt32) -> Data {
            withUnsafeBytes(of: value.littleEndian) { Data($0) }
        }
        let crx3 = Data("Cr24".utf8) + uint32(3) + uint32(5) + Data(repeating: 9, count: 5) + zip
        let crx2 = Data("Cr24".utf8) + uint32(2) + uint32(2) + uint32(3) + Data(repeating: 7, count: 5) + zip
        #expect(try CRXArchive.zipData(from: crx3) == zip)
        #expect(try CRXArchive.zipData(from: crx2) == zip)
        #expect(try CRXArchive.zipData(from: zip) == zip)
        #expect(throws: CRXArchive.Failure.self) { try CRXArchive.zipData(from: Data("not an extension".utf8)) }
    }

    @Test func recordsSayWhereTheyComeFrom() {
        let store = ExtensionRecord(
            source: .chromeWebStore(storeID: darkReader, packagePath: "/p/1.zip"), name: "Dark Reader", appName: nil
        )
        #expect(store.originText == "From the Chrome Web Store")
        #expect(store.storeID == darkReader)
        #expect(store.bundleIdentifier == nil)
        #expect(store.path == "/p/1.zip")
    }
}

struct ExtensionUpdateTests {
    @Test func versionsCompareNumberByNumber() {
        #expect(ExtensionVersion.isNewer("4.9.110", than: "4.9.99"))
        #expect(ExtensionVersion.isNewer("2026.10.1", than: "2026.10"))
        #expect(!ExtensionVersion.isNewer("1.0", than: "1.0.0"))
        #expect(!ExtensionVersion.isNewer("1.2", than: "1.10"))
    }

    @Test func oneCheckAsksForEveryExtension() throws {
        let url = try #require(ChromeWebStoreUpdates.checkURL(for: [
            (storeID: "aaaabbbbccccddddeeeeffffgggghhhh", version: "1.0"),
            (storeID: "iiiijjjjkkkkllllmmmmnnnnoooopppp", version: "2.3")
        ]))
        #expect(url.absoluteString.contains("response=updatecheck"))
        #expect(url.absoluteString.contains("x=id%3Daaaabbbbccccddddeeeeffffgggghhhh%26v%3D1.0%26uc"))
        #expect(url.absoluteString.contains("x=id%3Diiiijjjjkkkkllllmmmmnnnnoooopppp%26v%3D2.3%26uc"))
    }

    @Test func googlesAnswerGivesTheUpdates() {
        let answer = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gupdate xmlns="http://www.google.com/update2/response" protocol="2.0" server="prod">
          <app appid="aaaabbbbccccddddeeeeffffgggghhhh" status="ok">
            <updatecheck codebase="https://clients2.googleusercontent.com/crx/blobs/x/a.crx" status="ok" version="4.9.110"/>
          </app>
          <app appid="iiiijjjjkkkkllllmmmmnnnnoooopppp" status="ok">
            <updatecheck status="noupdate"/>
          </app>
        </gupdate>
        """
        let updates = ChromeWebStoreUpdates.parse(Data(answer.utf8))
        #expect(updates.count == 1)
        #expect(updates["aaaabbbbccccddddeeeeffffgggghhhh"]?.version == "4.9.110")
        #expect(updates["aaaabbbbccccddddeeeeffffgggghhhh"]?.downloadURL.host == "clients2.googleusercontent.com")
    }
}
