import Foundation
@testable import Ombre
import SwiftData
import Testing

/// Which tabs make a group of a site, and where groups show.
struct TabGroupingTests {
    private let ids = (0 ..< 6).map { _ in UUID() }

    @Test func threeTabsOfASiteMakeAGroup() {
        let tabs = [
            (id: ids[0], site: Optional("example.com")), (id: ids[1], site: "example.com"),
            (id: ids[2], site: "other.org"), (id: ids[3], site: "example.com"),
            (id: ids[4], site: "other.org"), (id: ids[5], site: nil)
        ]
        let groups = TabGrouping.siteGroups(tabs, grouped: [], groupedSites: [])
        #expect(groups.map(\.site) == ["example.com"])
        #expect(groups.first?.ids == [ids[0], ids[1], ids[3]])
    }

    /// A site already grouped takes its other tabs, even one.
    @Test func aGroupedSiteTakesItsOtherTabs() {
        let tabs = [(id: ids[0], site: Optional("example.com")), (id: ids[1], site: "example.com")]
        let groups = TabGrouping.siteGroups(tabs, grouped: [ids[0]], groupedSites: ["example.com"])
        #expect(groups.first?.ids == [ids[1]])
    }

    @Test func tabsTakenOutAndSitesUngroupedStayOut() {
        let tabs = (0 ..< 4).map { (id: ids[$0], site: Optional("example.com")) }
        #expect(TabGrouping.siteGroups(tabs, grouped: [], groupedSites: [], excluded: [ids[0], ids[1]]).isEmpty)
        #expect(TabGrouping.siteGroups(tabs, grouped: [], groupedSites: [], declined: ["example.com"]).isEmpty)
    }

    /// A group shows at its first tab, its tabs under it; one with a single
    /// tab left doesn't show.
    @Test func rowsPlaceAGroupAtItsFirstTab() {
        let group = UUID()
        let lonely = UUID()
        let rows = TabGrouping.rows(
            tabs: [ids[0], ids[1], ids[2], ids[3]],
            groups: [(id: group, tabs: [ids[3], ids[1]]), (id: lonely, tabs: [ids[2]])]
        )
        #expect(rows == [.tab(ids[0]), .group(group, tabs: [ids[1], ids[3]]), .tab(ids[2])])
    }

    @Test func onlyWebPagesHaveASite() throws {
        #expect(try TabGrouping.site(of: #require(URL(string: "https://mail.google.com/x"))) == "google.com")
        #expect(try TabGrouping.site(of: #require(URL(string: "file:///tmp/a.html"))) == nil)
    }
}

extension TabManagerTests {
    @MainActor
    struct TabGroups {
        private func tab(
            _ address: String,
            _ order: Int,
            in window: TabManagerTestWindow,
            type: TabType = .normal
        ) throws -> Tab {
            let space = try window.activeSpace
            return try window.tabManager.makeTab(
                url: #require(URL(string: address)),
                title: address,
                type: type,
                order: order,
                in: space,
                isPrivate: true
            )
        }

        private func groups(_ window: TabManagerTestWindow) throws -> [TabGroup] {
            try window.tabManager.tabGroups(in: window.activeSpace)
        }

        @Test func tidyGroupsThreeTabsOfASite() async throws {
            try await TabManagerTestWindow.run { window in
                let first = try tab("https://example.com/1", 5, in: window)
                let second = try tab("https://www.example.com/2", 4, in: window)
                _ = try tab("https://other.org/", 3, in: window)
                let third = try tab("https://example.com/3", 2, in: window)
                _ = try tab("https://example.com/pinned", 0, in: window, type: .pinned)
                _ = try tab("https://other.org/2", 1, in: window)

                try window.tabManager.tidyTabs(in: window.activeSpace)

                let made = try groups(window)
                #expect(made.count == 1)
                #expect(made.first?.name == "example.com")
                #expect(made.first?.tabIDs == [first.id, second.id, third.id])
            }
        }

        @Test func takenOutUngroupedAndClosed() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = try (0 ..< 4).map { try tab("https://example.com/\($0)", 4 - $0, in: window) }
                let manager = window.tabManager
                let space = try window.activeSpace
                manager.tidyTabs(in: space)
                let group = try #require(try groups(window).first)

                manager.removeFromGroup(tabs[0])
                #expect(group.tabIDs == [tabs[1].id, tabs[2].id, tabs[3].id])
                #expect(group.releasedTabIDs == [tabs[0].id])
                #expect(manager.tabGroup(of: tabs[0]) == nil)

                manager.renameTabGroup(group, to: "  Reading  ")
                #expect(group.name == "Reading")

                manager.ungroup(group)
                #expect(try groups(window).isEmpty)
                #expect(manager.tabGroup(of: tabs[1]) == nil)

                // Tidy Tabs Now groups them again, the tab taken out too.
                manager.tidyTabs(in: space)
                let again = try #require(try groups(window).first)
                #expect(Set(again.tabIDs) == Set(tabs.map(\.id)))

                manager.closeTabGroup(again, in: space)
                for tab in tabs {
                    await window.waitUntilClosed(tab)
                }
                #expect(try groups(window).isEmpty)
            }
        }

        /// Two tabs left out of three: no more group.
        @Test func aGroupLeftWithOneTabIsUngrouped() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = try (0 ..< 3).map { try tab("https://example.com/\($0)", 3 - $0, in: window) }
                try window.tabManager.tidyTabs(in: window.activeSpace)
                window.tabManager.removeFromGroup(tabs[0])
                window.tabManager.removeFromGroup(tabs[1])
                #expect(try groups(window).isEmpty)
            }
        }

        @Test func aDeletedSpacesGroupsGo() async throws {
            try await TabManagerTestWindow.run { window in
                let space = window.createSpace("Other")
                window.tabManager.activateContainer(space)
                for index in 0 ..< 3 {
                    _ = try tab("https://example.com/\(index)", index, in: window)
                }
                window.tabManager.tidyTabs(in: space)
                #expect(try groups(window).count == 1)
                window.tabManager.deleteContainer(space)
                let left = try window.modelContext.fetch(FetchDescriptor<TabGroup>())
                #expect(left.isEmpty)
            }
        }
    }
}
