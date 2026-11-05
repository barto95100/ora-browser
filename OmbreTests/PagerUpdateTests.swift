import AppKit
import Combine
import Foundation
@testable import Ombre
import SwiftUI
import Testing

/// The spaces' pager in the sidebar (`NSPageView`): AppKit crashed inside a
/// transition started with no page in place, or toward the page already
/// shown, while a page's view was laid out.
struct PagerUpdateTests {
    private func plan(
        current: (count: Int, index: Int) = (3, 1),
        new: (count: Int, index: Int) = (3, 1),
        pagesChanged: Bool = false,
        animated: Bool = true,
        isAnimating: Bool = false,
        isOnScreen: Bool = true
    ) -> PagerUpdate {
        PagerUpdate.plan(
            currentCount: current.count, currentIndex: current.index,
            newCount: new.count, newIndex: new.index,
            pagesChanged: pagesChanged, wantsAnimation: animated,
            isAnimating: isAnimating, isOnScreen: isOnScreen
        )
    }

    @Test func animatesOnlyToAnotherPageAskedFor() {
        #expect(plan(new: (3, 2)) == .animate(index: 2))
        #expect(plan(new: (3, 2), animated: false) == .show(index: 2))
    }

    /// The crash: a transition toward the page already shown.
    @Test func samePageIsNotAnimated() {
        #expect(plan(new: (3, 1)) == .none)
        #expect(plan(new: (3, 1), pagesChanged: true) == .show(index: 1))
    }

    @Test func noTransitionWithoutPagesOrOffScreen() {
        #expect(plan(current: (0, 0), new: (3, 1)) == .show(index: 1))
        #expect(plan(new: (3, 2), isOnScreen: false) == .show(index: 2))
        #expect(plan(new: (0, 0)) == .clear)
        #expect(plan(current: (0, 0), new: (0, 0)) == .none)
    }

    @Test func outOfRangeIndexIsKeptInRange() {
        #expect(plan(new: (3, 7), animated: false) == .show(index: 2))
        #expect(plan(new: (3, -1), animated: false) == .show(index: 0))
    }

    /// New pages (a space added or deleted) while the old ones are shown:
    /// never animated, the pages change under the transition.
    @Test func newPagesAreShownWithoutTransition() {
        #expect(plan(new: (4, 2), pagesChanged: true) == .show(index: 2))
    }

    /// A pager made for a space other than the first shows it at once: it
    /// used to start on page 0, then animate to it while laid out.
    @MainActor
    @Test func pagerStartsOnTheSelectedPage() async {
        let controller = NSPageViewContainerController<String, EmptyView>()
        controller.pageObjects = ["a", "b", "c"]
        controller.idFromObject = { $0 }
        controller.idToObject = { [weak controller] id in controller?.pageObjects.first { $0 == id } }
        controller.objectToView = { _ in EmptyView() }
        controller.initialIndex = 1
        _ = controller.view

        #expect(controller.selectedIndex == 1)

        // Same pages and page asked again (a redraw): nothing moves.
        controller.request(pageObjects: ["a", "b", "c"], index: 1, animated: true)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(!controller.isAnimating)
        #expect(controller.selectedIndex == 1)
    }

    @Test func nothingChangesDuringATransition() {
        #expect(plan(new: (3, 2), isAnimating: true) == .wait)
        #expect(plan(new: (0, 0), isAnimating: true) == .wait)
    }
}

extension TabManagerTests {
    /// Closing a loaded pinned tab, then showing it again, stays in its
    /// space: the sidebar's pager has no reason to move (the crash came from
    /// the pager, not from a change of space; this guards `TabManager`).
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
