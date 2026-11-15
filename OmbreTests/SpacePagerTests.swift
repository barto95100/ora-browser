import AppKit
import Combine
import Foundation
@testable import Ombre
import SwiftUI
import Testing

/// The spaces' pager in the sidebar (`SpacePager`): plain SwiftUI since
/// AppKit's page controller crashed three times (a transition with no page
/// in place, a new space shown at once, and the sidebar changing during its
/// own swipe tracking).
struct SpacePagerLayoutTests {
    @Test func drawsOnlyTheSelectedPage() {
        let layout = SpacePagerLayout(count: 3, selection: 1, leaving: nil)
        #expect((0 ..< 3).filter(layout.draws) == [1])
        #expect(layout.offset(width: 200) == -200)
    }

    /// The page left stays drawn while the move runs.
    @Test func drawsThePageLeftDuringAMove() {
        let layout = SpacePagerLayout(count: 4, selection: 3, leaving: 0)
        #expect((0 ..< 4).filter(layout.draws) == [0, 3])
    }

    /// A space deleted, or none left: never a page out of range.
    @Test func keepsEverythingInRange() {
        #expect(SpacePagerLayout(count: 3, selection: 7, leaving: 5).index == 2)
        #expect(SpacePagerLayout(count: 3, selection: 7, leaving: 5).leaving == nil)
        #expect(SpacePagerLayout(count: 3, selection: -1, leaving: nil).index == 0)
        #expect(SpacePagerLayout(count: 0, selection: 2, leaving: 1).index == 0)
        #expect(SpacePagerLayout(count: 0, selection: 2, leaving: 1).leaving == nil)
        #expect(SpacePagerLayout(count: 2, selection: 1, leaving: 1).leaving == nil)
    }
}

extension TabManagerTests {
    /// Closing a loaded pinned tab, then showing it again, stays in its
    /// space: the sidebar's pager has no reason to move.
    @MainActor
    struct PinnedReload {
        @Test func pinnedTabClosedThenShownStaysInItsSpace() async throws {
            try await TabManagerTestWindow.runTwo { window, _ in
                _ = window.createSpace("Before")
                let space = window.createSpace("Work")
                window.tabManager.activateContainer(space)
                let pinned = try await window.openLoaded("pinned")
                window.tabManager.togglePinTab(pinned)
                var spaces: [UUID?] = []
                let observation = window.tabManager.$activeContainer.sink { spaces.append($0?.id) }
                defer { observation.cancel() }

                await window.close(pinned)
                window.tabManager.activateTab(pinned)
                await window.waitUntil("loaded again") { pinned.isWebViewReady }
                await window.waitUntil("caught up") { window.tabManager.pendingSync == nil }

                #expect(spaces.allSatisfy { $0 == space.id }, "spaces shown: \(spaces)")
            }
        }
    }
}

extension TabManagerTests {
    /// The crash of 15/11: a tab closed while the sidebar moved to another
    /// space (a swipe). In a real browser window, the same change of space
    /// as a swipe (animated), with the tab closed in the middle of it, then
    /// a space deleted during the next move.
    @MainActor
    @Suite(.serialized)
    struct SpaceChangeDuringClose {
        @Test func closingATabDuringASpaceChange() async throws {
            try await TabManagerTestWindow.run { managers in
                let first = try managers.activeSpace
                let closing = try await managers.openLoaded("closing")
                let staying = try await managers.openLoaded("staying")
                let second = managers.createSpace("Second")
                managers.addUnloadedTab("/other", order: 0, in: second)
                let window = try await BrowserTestWindow.open(managers)
                defer { window.close() }
                await window.settle()

                withAnimation(.easeOut(duration: 0.3)) {
                    managers.tabManager.activateContainer(second)
                }
                await window.settle()
                managers.tabManager.closeTab(tab: closing)
                await window.settle()
                await managers.waitUntilClosed(closing)

                let third = managers.createSpace("Third")
                await window.settle()
                withAnimation(.easeOut(duration: 0.3)) {
                    managers.tabManager.activateContainer(first)
                }
                await window.settle()
                managers.modelContext.delete(third)
                try managers.modelContext.save()
                try await Task.sleep(for: .milliseconds(700))
                await window.settle()

                #expect(managers.tabManager.activeContainer?.id == first.id)
                #expect(first.tabs.contains { $0.id == staying.id })
                #expect(!first.tabs.contains { $0.id == closing.id })
                #expect(window.sidebarFrame != nil)
            }
        }
    }
}
