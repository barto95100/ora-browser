import AppKit
import Foundation
@testable import Ombre
import Testing

/// Extensions and private windows: what is decided there stays in memory,
/// and an extension not allowed in private can't open a tab there.
@MainActor
struct ExtensionPrivateAccessTests {
    @Test func privateDecisionsAreKeptPerExtensionAndForgotten() {
        var decisions = PrivateSiteDecisions()

        decisions.set(.allow, for: "example.com", extensionID: "one")
        decisions.set(.deny, for: "tracker.net", extensionID: "one")

        #expect(decisions.decision(for: "example.com", extensionID: "one") == .allow)
        #expect(decisions.decision(for: "tracker.net", extensionID: "one") == .deny)
        #expect(decisions.decision(for: "example.com", extensionID: "two") == nil)
        #expect(decisions.extensionIDs == ["one"])

        decisions.removeAll()

        #expect(decisions.decision(for: "example.com", extensionID: "one") == nil)
        #expect(decisions.extensionIDs.isEmpty)
    }

    @Test func allSitesFromAPrivateWindowCoversEveryHost() {
        var decisions = PrivateSiteDecisions()

        decisions.set(.allow, for: PrivateSiteDecisions.allSites, extensionID: "one")

        #expect(decisions.decision(for: "anything.org", extensionID: "one") == .allow)
    }

    @Test func aDecisionFromAPrivateTabStaysInMemory() {
        guard #available(macOS 15.4, *) else { return }
        let manager = WebExtensionsManager.shared
        let record = ExtensionRecord(
            id: "test-\(UUID().uuidString)", source: .file(packagePath: "/dev/null"), name: "Test", appName: nil
        )
        defer { manager.privateSiteDecisions.removeAll() }

        manager.decideSite("example.com", .allow, id: record.id, isPrivate: true)
        manager.decideSite("regular.com", .allow, id: record.id, isPrivate: false)

        // A private tab sees it; a regular one still asks, from the record.
        #expect(manager.siteDecision(for: "example.com", in: record, isPrivate: true) == .allow)
        #expect(manager.siteDecision(for: "example.com", in: record, isPrivate: false) == .ask)
        // A regular tab's decision goes to the record, not to memory.
        #expect(manager.privateSiteDecisions.decision(for: "regular.com", extensionID: record.id) == nil)

        manager.forgetPrivateSiteDecisions()

        #expect(manager.siteDecision(for: "example.com", in: record, isPrivate: true) == .ask)
    }

    @Test func aPrivateOneDayDecisionExpires() {
        var decisions = PrivateSiteDecisions()
        let now = Date()

        decisions.set(.allow, for: "example.com", until: now.addingTimeInterval(60), extensionID: "one")

        #expect(decisions.decision(for: "example.com", extensionID: "one", at: now) == .allow)
        #expect(decisions.decision(for: "example.com", extensionID: "one", at: now.addingTimeInterval(120)) == nil)
        #expect(decisions.entries(for: "one", at: now.addingTimeInterval(120)).isEmpty)
    }

    @Test func anExpiredHostDecisionFallsBackToAllSites() {
        var decisions = PrivateSiteDecisions()
        let now = Date()
        decisions.set(.allow, for: PrivateSiteDecisions.allSites, extensionID: "one")
        decisions.set(.deny, for: "example.com", until: now.addingTimeInterval(60), extensionID: "one")

        #expect(decisions.decision(for: "example.com", extensionID: "one", at: now) == .deny)
        #expect(decisions.decision(for: "example.com", extensionID: "one", at: now.addingTimeInterval(120)) == .allow)
    }

    @Test func askForgetsAPrivateDecision() {
        var decisions = PrivateSiteDecisions()
        decisions.set(.deny, for: "example.com", extensionID: "one")

        decisions.set(.ask, for: "example.com", extensionID: "one")

        #expect(decisions.decision(for: "example.com", extensionID: "one") == nil)
        #expect(decisions.extensionIDs.isEmpty)
    }

    @Test func aTabOpensInAPrivateWindowOnlyWhenAllowed() async throws {
        guard #available(macOS 15.4, *) else { return }
        try await TabManagerTestWindow.run { session in
            let manager = WebExtensionsManager.shared
            let privateWindow = ExtensionWindow(
                window: NSWindow(), tabManager: session.tabManager, isPrivate: true, manager: manager
            )
            let normalWindow = ExtensionWindow(
                window: NSWindow(), tabManager: session.tabManager, isPrivate: false, manager: manager
            )

            // Not allowed in private: the front normal window, never the private one.
            #expect(WebExtensionsManager.window(
                for: nil, focused: privateWindow, focusedNormal: normalWindow, allowsPrivate: false
            ) === normalWindow)
            #expect(WebExtensionsManager.window(
                for: privateWindow, focused: privateWindow, focusedNormal: normalWindow, allowsPrivate: false
            ) == nil)
            // Allowed: wherever it asks, or the front window.
            #expect(WebExtensionsManager.window(
                for: nil, focused: privateWindow, focusedNormal: normalWindow, allowsPrivate: true
            ) === privateWindow)
            #expect(WebExtensionsManager.window(
                for: privateWindow, focused: normalWindow, focusedNormal: normalWindow, allowsPrivate: true
            ) === privateWindow)
        }
    }
}
