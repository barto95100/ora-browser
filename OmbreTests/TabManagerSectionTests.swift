import Foundation
@testable import Ombre
import SwiftData
import Testing

extension TabManagerTests {
    /// Moving tabs within and between the sections of a space (favorites,
    /// pinned, normal), as the sidebar's drag and drop does, and between spaces.
    @MainActor
    struct Move {
        @Test func movingWithinNormalSectionRenumbersOnlyThatSection() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let first = window.addUnloadedTab("first", order: 3, in: space)
                let second = window.addUnloadedTab("second", order: 2, in: space)
                let third = window.addUnloadedTab("third", order: 1, in: space)
                let favorite = window.addUnloadedTab("favorite", type: .fav, order: 7, in: space)
                let pinned = window.addUnloadedTab("pinned", type: .pinned, order: 9, in: space)

                // Dragged down: after the target.
                space.moveTab(first, onto: third)
                #expect(window.section(.normal, of: space) == [second.id, third.id, first.id])
                #expect([second.order, third.order, first.order] == [Int]([3, 2, 1]))

                // Dragged up: before the target.
                space.moveTab(first, onto: second)
                #expect(window.section(.normal, of: space) == [first.id, second.id, third.id])

                #expect(favorite.order == 7)
                #expect(pinned.order == 9)
            }
        }

        @Test func movingToFavoritesThenPinnedChangesSection() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let moved = window.addUnloadedTab("moved", order: 1, in: space)
                let favorite = window.addUnloadedTab("favorite", type: .fav, order: 1, in: space)
                let pinned = window.addUnloadedTab("pinned", type: .pinned, order: 1, in: space)

                space.moveTab(moved, onto: favorite)
                #expect(moved.type == .fav)
                #expect(moved.savedURL == moved.url)
                // From another section, it takes the target's place.
                #expect(window.section(.fav, of: space) == [moved.id, favorite.id])

                space.moveTab(moved, onto: pinned)
                #expect(moved.type == .pinned)
                #expect(moved.savedURL == moved.url)
                #expect(moved.folderID == nil)
                #expect(space.visiblePinnedTabs(activeTabID: nil).map(\.id) == [moved.id, pinned.id])
                #expect(window.section(.fav, of: space) == [favorite.id])
            }
        }

        @Test func movingPinnedTabToEndOfNormalTabsLeavesItsFolder() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let normal = window.addUnloadedTab("normal", order: 1, in: space)
                let pinned = window.addUnloadedTab("pinned", type: .pinned, order: 1, in: space)
                let folder = window.tabManager.createFolder(in: space, with: pinned)
                #expect(pinned.folderID == folder.id)

                space.moveToEndOfNormalTabs(pinned)

                #expect(pinned.type == .normal)
                #expect(pinned.folderID == nil)
                #expect(pinned.savedURL == nil)
                #expect(window.section(.normal, of: space) == [normal.id, pinned.id])
            }
        }

        @Test func movingActiveTabToAnotherSpace() async throws {
            try await TabManagerTestWindow.run { window in
                let defaultSpace = try window.activeSpace
                let work = window.createSpace("Work")
                window.addUnloadedTab("work", order: 1, in: work)
                window.tabManager.activateContainer(defaultSpace)
                window.addUnloadedTab("stays", order: 1, in: defaultSpace)
                let moved = try await window.openLoaded("moved")
                window.tabManager.togglePinTab(moved)
                window.tabManager.createFolder(in: defaultSpace, with: moved)
                let order = moved.order

                window.tabManager.moveTabToContainer(moved, toContainer: work)

                #expect(moved.container.id == work.id)
                #expect(work.tabs.contains { $0.id == moved.id })
                #expect(!defaultSpace.tabs.contains { $0.id == moved.id })
                #expect(moved.folderID == nil)
                #expect(moved.type == .pinned)
                #expect(moved.order == order)
                // BUG: the moved tab stays active while the active space is still
                // the old one: the window shows a tab of a space it does not show.
                #expect(window.tabManager.activeTab?.id == moved.id)
                #expect(window.tabManager.activeContainer?.id == defaultSpace.id)
            }
        }
    }

    /// Pinning and adding to favorites.
    @MainActor
    struct PinAndFavorite {
        @Test func togglePinTabRoundTrip() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let firstPinned = window.addUnloadedTab("pinned1", type: .pinned, order: 2, in: space)
                window.addUnloadedTab("pinned2", type: .pinned, order: 1, in: space)
                let tab = window.addUnloadedTab("tab", order: 2, in: space)

                window.tabManager.togglePinTab(tab)

                #expect(tab.type == .pinned)
                #expect(tab.savedURL == tab.url)
                // BUG: (ONG-14) the tab keeps its order from the normal section, so
                // it lands anywhere among the pinned tabs, here tied with "pinned1".
                #expect(tab.order == 2)
                #expect(firstPinned.order == 2)

                let folder = window.tabManager.createFolder(in: space, with: tab)
                #expect(tab.folderID == folder.id)

                window.tabManager.togglePinTab(tab)

                #expect(tab.type == .normal)
                #expect(tab.savedURL == nil)
                #expect(tab.folderID == nil)
            }
        }

        @Test func toggleFavTabRoundTrip() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let tab = window.addUnloadedTab("tab", order: 1, in: space)
                let order = tab.order

                window.tabManager.toggleFavTab(tab)
                #expect(tab.type == .fav)
                #expect(tab.savedURL == tab.url)
                #expect(tab.order == order)

                window.tabManager.toggleFavTab(tab)
                #expect(tab.type == .normal)
                #expect(tab.savedURL == nil)
            }
        }

        @Test func toggleFavTabTakesPinnedTabOutOfItsFolder() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let pinned = window.addUnloadedTab("pinned", type: .pinned, order: 1, in: space)
                pinned.savedURL = TabManagerTestWindow.url("saved")
                window.tabManager.createFolder(in: space, with: pinned)

                window.tabManager.toggleFavTab(pinned)

                #expect(pinned.type == .fav)
                #expect(pinned.folderID == nil)
                // The saved address becomes the current one.
                #expect(pinned.savedURL == pinned.url)

                window.tabManager.toggleFavTab(pinned)
                #expect(pinned.type == .normal)
                #expect(pinned.savedURL == nil)
            }
        }
    }

    /// Duplicating a tab (context menu).
    @MainActor
    struct Duplicate {
        @Test func duplicateGoesRightAfterOriginalLoadedButNotActive() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let original = try await window.openLoaded("original")
                let middle = try await window.openLoaded("middle")
                let active = try await window.openLoaded("active")

                window.tabManager.duplicateTab(original)

                let copy = try #require(space.tabs.first {
                    $0.id != original.id && $0.url == original.url
                })
                #expect(window.tabManager.activeTab?.id == active.id)
                #expect(copy.type == .normal)
                #expect(window.section(.normal, of: space) == [active.id, middle.id, original.id, copy.id])
                // Loaded in the background (`loadSilently`).
                #expect(copy.browserPage != nil)
                await window.waitUntil("copy loaded") { copy.isWebViewReady }
            }
        }

        @Test func duplicatingPinnedTabPinsTheCopyInTheSameFolder() async throws {
            try await TabManagerTestWindow.run { window in
                let space = try window.activeSpace
                let pinned = window.addUnloadedTab("pinned", type: .pinned, order: 2, in: space)
                let below = window.addUnloadedTab("below", type: .pinned, order: 1, in: space)
                let folder = window.tabManager.createFolder(in: space, with: pinned)
                window.tabManager.moveTab(below, toFolder: folder)

                window.tabManager.duplicateTab(pinned)

                let copy = try #require(space.tabs.first {
                    $0.id != pinned.id && $0.url == pinned.url
                })
                #expect(copy.type == .pinned)
                #expect(copy.savedURL == copy.url)
                #expect(copy.folderID == folder.id)
                #expect(space.tabs(in: folder).map(\.id) == [pinned.id, copy.id, below.id])
            }
        }
    }
}
