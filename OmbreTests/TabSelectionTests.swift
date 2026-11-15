import AppKit
import Combine
import Foundation
@testable import Ombre
import Testing

extension TabManagerTests {
    /// Several tabs selected in the sidebar (⌘-click, ⇧-click), and what is
    /// done to them together.
    @MainActor
    struct TabSelection {
        /// Favorite, pinned (one in a folder), then normal tabs: the order the
        /// sidebar shows.
        private struct Tabs {
            let fav: Tab
            let pinned: Tab
            let inFolder: Tab
            let normal: [Tab]
        }

        private func makeTabs(in window: TabManagerTestWindow) throws -> Tabs {
            let space = try window.activeSpace
            let fav = window.addUnloadedTab("/fav", type: .fav, order: 0, in: space)
            let pinned = window.addUnloadedTab("/pinned", type: .pinned, order: 1, in: space)
            let inFolder = window.addUnloadedTab("/in-folder", type: .pinned, order: 0, in: space)
            window.tabManager.createFolder(in: space, with: inFolder)
            let normal = (0 ..< 3).map { window.addUnloadedTab("/normal\($0)", order: 3 - $0, in: space) }
            return Tabs(fav: fav, pinned: pinned, inFolder: inFolder, normal: normal)
        }

        private func ids(_ tabs: [Tab]) -> [UUID] {
            tabs.map(\.id)
        }

        @Test func sidebarOrderIsTopToBottom() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = try makeTabs(in: window)
                let space = try window.activeSpace
                #expect(ids(window.tabManager.sidebarOrder(in: space))
                    == ids([tabs.fav, tabs.pinned, tabs.inFolder] + tabs.normal))

                // A closed folder shows none of its tabs (the active one aside).
                let folder = try #require(space.folder(of: tabs.inFolder))
                window.tabManager.toggleFolder(folder)
                #expect(ids(window.tabManager.sidebarOrder(in: space)) == ids([tabs.fav, tabs.pinned] + tabs.normal))
                window.tabManager.activateTab(tabs.inFolder)
                #expect(ids(window.tabManager.sidebarOrder(in: space))
                    == ids([tabs.fav, tabs.pinned, tabs.inFolder] + tabs.normal))
            }
        }

        @Test func aSplitRowsTabsAreTogether() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = try makeTabs(in: window)
                window.tabManager.openInSplitView(left: tabs.normal[0], right: tabs.normal[2])
                let order = try ids(window.tabManager.sidebarOrder(in: window.activeSpace))
                #expect(order.suffix(3) == ids([tabs.normal[0], tabs.normal[2], tabs.normal[1]]))
            }
        }

        /// ⌘-click: the tab shown counts as selected; again: taken out.
        @Test func commandClickAddsAndRemoves() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = try makeTabs(in: window)
                let manager = window.tabManager
                manager.activateTab(tabs.normal[0])

                #expect(manager.handleSidebarClick(on: tabs.normal[2], .toggle))
                #expect(manager.selectedTabIDs == [tabs.normal[0].id, tabs.normal[2].id])
                #expect(manager.activeTab?.id == tabs.normal[0].id)
                manager.handleSidebarClick(on: tabs.pinned, .toggle)
                manager.handleSidebarClick(on: tabs.normal[0], .toggle)
                #expect(ids(manager.selectedTabs) == ids([tabs.pinned, tabs.normal[2]]))
            }
        }

        /// ⇧-click: from the last tab ⌘-clicked (else the active one).
        @Test func shiftClickSelectsARange() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = try makeTabs(in: window)
                let manager = window.tabManager
                manager.activateTab(tabs.pinned)

                #expect(manager.handleSidebarClick(on: tabs.normal[1], .range))
                #expect(ids(manager.selectedTabs) == ids([tabs.pinned, tabs.inFolder, tabs.normal[0], tabs.normal[1]]))
                // From the same start, the other way.
                manager.handleSidebarClick(on: tabs.fav, .range)
                #expect(ids(manager.selectedTabs) == ids([tabs.fav, tabs.pinned]))

                manager.handleSidebarClick(on: tabs.normal[2], .toggle)
                manager.handleSidebarClick(on: tabs.normal[0], .range)
                #expect(ids(manager.selectedTabs) == ids(Array(tabs.normal)))
            }
        }

        @Test func aPlainClickOrAnotherSpaceEndsIt() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = try makeTabs(in: window)
                let manager = window.tabManager
                manager.activateTab(tabs.normal[0])
                manager.handleSidebarClick(on: tabs.normal[1], .toggle)
                #expect(!manager.handleSidebarClick(on: tabs.normal[2], .plain))
                #expect(manager.selectedTabIDs.isEmpty)

                manager.handleSidebarClick(on: tabs.normal[1], .toggle)
                let other = window.createSpace("Other")
                manager.activateContainer(other)
                #expect(manager.selectedTabIDs.isEmpty)
            }
        }

        /// The context menu acts on the selection only from one of its tabs.
        @Test func theMenuActsOnTheSelectionFromOneOfItsTabs() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = try makeTabs(in: window)
                let manager = window.tabManager
                manager.activateTab(tabs.normal[0])
                manager.handleSidebarClick(on: tabs.normal[1], .toggle)
                #expect(ids(manager.menuTabs(for: tabs.normal[1])) == ids([tabs.normal[0], tabs.normal[1]]))
                #expect(ids(manager.menuTabs(for: tabs.normal[2])) == ids([tabs.normal[2]]))
                #expect(TabAddresses.text(for: manager.selectedTabs)
                    == "\(tabs.normal[0].url.absoluteString)\n\(tabs.normal[1].url.absoluteString)")
            }
        }

        @Test func pinUnpinAndMoveTogether() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = try makeTabs(in: window)
                let manager = window.tabManager
                let space = try window.activeSpace

                manager.setPinned([tabs.normal[0], tabs.normal[1]], true)
                #expect(tabs.normal[0].type == .pinned && tabs.normal[1].type == .pinned)
                #expect(manager.selectedTabIDs.isEmpty)
                manager.setPinned([tabs.normal[0], tabs.pinned], false)
                #expect(tabs.normal[0].type == .normal && tabs.pinned.type == .normal)

                let folder = try #require(space.folder(of: tabs.inFolder))
                manager.moveTabs([tabs.normal[2], tabs.fav], toFolder: folder)
                #expect(space.folder(of: tabs.normal[2])?.id == folder.id)
                #expect(space.folder(of: tabs.fav)?.id == folder.id)

                let other = window.createSpace("Other")
                manager.activateContainer(space)
                manager.moveTabs([tabs.normal[0], tabs.normal[1]], to: other)
                #expect(tabs.normal[0].container.id == other.id && tabs.normal[1].container.id == other.id)
            }
        }

        @Test func twoTabsOpenInSplitView() async throws {
            try await TabManagerTestWindow.run { window in
                let tabs = try makeTabs(in: window)
                let manager = window.tabManager
                #expect(!manager.canOpenInSplitView([tabs.normal[0]]))
                #expect(!manager.canOpenInSplitView(Array(tabs.normal)))
                manager.openInSplitView([tabs.normal[2], tabs.normal[0]])
                #expect(manager.split(containing: tabs.normal[2])?.right.id == tabs.normal[0].id)
                #expect(manager.activeTab?.id == tabs.normal[2].id)
            }
        }

        /// The tab shown among them goes last: no other of them is shown on
        /// the way.
        @Test func closeTogether() async throws {
            try await TabManagerTestWindow.run { window in
                let kept = try await window.openLoaded("kept")
                let first = try await window.openLoaded("first")
                let second = try await window.openLoaded("second")
                window.tabManager.activateTab(first)
                var shown: [UUID?] = []
                let observation = window.tabManager.$activeTab.sink { shown.append($0?.id) }
                defer { observation.cancel() }
                window.tabManager.closeTabs([first, second])
                await window.waitUntilClosed(first)
                await window.waitUntilClosed(second)
                #expect(!window.isDeleted(kept))
                #expect(!shown.contains(second.id))
                #expect(window.tabManager.activeTab?.id == kept.id)
            }
        }

        /// Unpinned, they keep their order (each goes first of the others).
        @Test func unpinningKeepsTheOrder() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let pinned = (0 ..< 3).map { window.addUnloadedTab("/p\($0)", type: .pinned, order: 3 - $0, in: space) }
                window.tabManager.setPinned(pinned, false)
                let normal = window.tabManager.sidebarOrder(in: space).filter { $0.type == .normal }
                #expect(ids(Array(normal.prefix(3))) == ids(pinned))
            }
        }

        /// A tab closed on its own leaves the selection.
        @Test func aTabClosedLeavesTheSelection() async throws {
            try await TabManagerTestWindow.run { window in
                let first = try await window.openLoaded("first")
                let second = try await window.openLoaded("second")
                window.tabManager.handleSidebarClick(on: first, .toggle)
                window.tabManager.closeTab(tab: first)
                #expect(window.tabManager.selectedTabIDs == [second.id])
            }
        }
    }
}

/// What a click's modifier keys do, and what VoiceOver says of the selection.
struct TabSelectionClickTests {
    @Test func modifierKeysPickTheClick() {
        #expect(TabManager.SelectionClick([]) == .plain)
        #expect(TabManager.SelectionClick(.command) == .toggle)
        #expect(TabManager.SelectionClick(.shift) == .range)
        #expect(TabManager.SelectionClick([.shift, .command]) == .range)
        // Other keys don't select.
        #expect(TabManager.SelectionClick(.option) == .plain)
    }

    @Test func voiceOverHearsTheSelection() {
        #expect(TabAccessibility.value(isLoaded: true, isPlayingMedia: false, isInSelection: true) == "In selection")
        #expect(TabSelectionAccessibility.announcement(count: 0) == "Selection cleared")
        #expect(TabSelectionAccessibility.announcement(count: 3) == "3 tabs selected")
    }
}
