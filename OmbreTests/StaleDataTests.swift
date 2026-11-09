import Foundation
@testable import Ombre
import Testing
import WebKit

/// At launch, only data Ombre identified as no longer used is removed
/// (lot F, Ludo's rule: never at random).
struct StaleDataTests {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func onlyOlderVersionsAndTheOldAppsListsAreStale() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ContentBlockerArtifactStore(baseURL: folder)
        let coverage = FilterListCoverage(
            totalRuleCount: 1, convertedRuleCount: 1, skippedRuleCount: 0, safariRuleCount: 1, shardCount: 1
        )
        try store.storeCompiledArtifacts(jsonShards: ["[]"], coverage: coverage, for: "adguard-base", revision: "aaa")
        let current = try #require(store.ruleListIdentifiers(for: "adguard-base", revision: "aaa").first)
        let older = current.replacingOccurrences(of: ".aaa.", with: ".bbb.")

        #expect(!store.isStale(ruleList: current))
        #expect(store.isStale(ruleList: older))
        #expect(store.isStale(ruleList: "com.orabrowser.adblock.adguard-base.62f088c59d92124f.0"))
        #expect(store.isStale(ruleList: "com.orabrowser.privacy.trackers.v1"))
        // Never one Ombre can't name.
        #expect(!store.isStale(ruleList: "com.apple.WebPrivacy.ResourceMonitorURLsRuleList"))
        #expect(!store.isStale(ruleList: AppIdentity.identifier("privacy.trackers.v1")))
        #expect(!store.isStale(ruleList: "com.example.other"))
        // The revision in use, even while its files are written again.
        #expect(!store.isStale(ruleList: older, activeRevisions: ["adguard-base": "bbb"]))
    }

    /// An extensions registry that can't be read gives no list: nothing is
    /// then removed as orphaned.
    @Test func anUnreadableRegistryKnowsNothingInstalled() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let registry = ExtensionRegistry(fileURL: folder.appendingPathComponent("extensions.json"))
        #expect(registry.read() == nil)
        try Data("not json".utf8).write(to: registry.fileURL)
        #expect(registry.read() == nil)
        registry.save([])
        #expect(registry.read()?.isEmpty == true)
    }

    @Test func onlyFoldersOfExtensionsMissingFromTheRegistryAreOrphans() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = UUID()
        let installed = UUID().uuidString
        let removed = UUID().uuidString
        let oldStore = UUID().uuidString
        let movedStore = UUID().uuidString
        let fileManager = FileManager.default
        func folder(_ path: String) throws {
            try fileManager.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try folder("\(current.uuidString)/\(installed)")
        try folder("\(current.uuidString)/\(removed)")
        try folder("\(current.uuidString)/NotAnExtension")
        try folder("\(oldStore)/\(UUID().uuidString)")
        try Data().write(to: root.appendingPathComponent("\(oldStore)/StaleExtensionOriginsCleared"))
        // An earlier store with an extension still installed: kept.
        try folder("\(movedStore)/\(installed.lowercased())")
        try folder("NotAStore/\(UUID().uuidString)")

        let orphans = ExtensionDataFolder.orphans(in: root, keeping: [installed], currentStore: current)
            .map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
        #expect(Set(orphans) == ["\(current.uuidString)/\(removed)", oldStore])
    }

    @Test func nothingIsAnOrphanWithoutWebKitsFolder() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(ExtensionDataFolder.orphans(in: missing, keeping: [], currentStore: UUID()).isEmpty)
    }

    @Test func sizesCountAFoldersContents() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(count: 100_000).write(to: folder.appendingPathComponent("a"))
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("b"),
            withIntermediateDirectories: true
        )
        try Data(count: 100_000).write(to: folder.appendingPathComponent("b/c"))
        #expect(StaleData.size(of: folder) >= 200_000)
    }

    /// For real, in the tests' own WebKit store: the old app's list goes,
    /// Ombre's privacy list stays.
    @MainActor
    @Test func staleRuleListsLeaveWebKitsStore() async throws {
        let store = try #require(WKContentRuleListStore.default())
        func compile(_ identifier: String) async throws {
            _ = try await store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: #"[{"trigger":{"url-filter":"stale-test"},"action":{"type":"block"}}]"#
            )
        }
        let legacy = "com.orabrowser.adblock.stale-test.0000000000000000.0"
        let kept = AppIdentity.identifier("stale-test.kept")
        try await compile(legacy)
        try await compile(kept)
        defer { store.removeContentRuleList(forIdentifier: kept) { _ in } }

        await BrowserPrivacyService.shared.removeStaleRuleLists()

        let left = await store.availableIdentifiers() ?? []
        #expect(!left.contains(legacy))
        #expect(left.contains(kept))
    }
}
