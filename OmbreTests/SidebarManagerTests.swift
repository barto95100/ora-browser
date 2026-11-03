import Foundation
@testable import Ombre
import Testing

struct SidebarManagerTests {
    @Test func hiddenSidebarStaysHiddenWhenItMovesRight() {
        #expect(SidebarManager.hiddenSide(.primary, from: .primary, to: .secondary) == .secondary)
    }

    @Test func hiddenSidebarStaysHiddenWhenItMovesLeft() {
        #expect(SidebarManager.hiddenSide(.secondary, from: .secondary, to: .primary) == .primary)
    }

    @Test func shownSidebarStaysShown() {
        #expect(SidebarManager.hiddenSide(nil, from: .primary, to: .secondary) == nil)
        #expect(SidebarManager.hiddenSide(nil, from: .secondary, to: .primary) == nil)
    }

    /// A window that already followed the move must not hide its page.
    @Test func windowThatAlreadyFollowedIsLeftAlone() {
        #expect(SidebarManager.hiddenSide(.secondary, from: .primary, to: .secondary) == .secondary)
    }

    @Test func obsoleteKeysAreRemoved() throws {
        let suiteName = "SidebarManagerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "ui.sidebar.hidden")
        defaults.set("primary", forKey: "ui.sidebar.visibility")
        defaults.set("secondary", forKey: "ui.sidebar.position")

        SidebarManager.removeObsoleteDefaults(defaults)

        #expect(defaults.object(forKey: "ui.sidebar.hidden") == nil)
        #expect(defaults.object(forKey: "ui.sidebar.visibility") == nil)
        #expect(defaults.string(forKey: "ui.sidebar.position") == "secondary")
    }
}
