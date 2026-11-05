import Foundation
@testable import Ombre
import Testing

/// The floating sidebar hides the mouse from the page under it in the web
/// view, without adding anything to the page (SEC-26). WebKit ignores
/// synthetic mouse moves (it reads the real pointer), so the page side is
/// a manual test.
struct MouseShieldTests {
    /// The same width as the floating sidebar: at least 200 points, at most
    /// 30 % of the window.
    @Test func coversTheSidebarSide() {
        let leading = MouseShield(edge: .leading, fraction: 0.1)
        #expect(leading.covers(windowX: 199, windowWidth: 1000)) // the minimum width wins
        #expect(!leading.covers(windowX: 201, windowWidth: 1000))
        // A narrow window: 30 % of 500, not 200 points.
        #expect(leading.covers(windowX: 149, windowWidth: 500))
        #expect(!leading.covers(windowX: 151, windowWidth: 500))

        let wide = MouseShield(edge: .leading, fraction: 0.5)
        #expect(!wide.covers(windowX: 451, windowWidth: 1500)) // at most 30 %

        let trailing = MouseShield(edge: .trailing, fraction: 0.2)
        #expect(trailing.covers(windowX: 1201, windowWidth: 1500))
        #expect(!trailing.covers(windowX: 1199, windowWidth: 1500))
    }

    @Test func pageIsToldOnceThatTheMouseLeft() {
        var tracker = MouseShieldTracker()
        #expect(tracker.mouseMoved(toX: 100, windowWidth: 1000) == .forward)

        // The sidebar shows over the left 300 points.
        tracker.shield = MouseShield(edge: .leading, fraction: 0.3)
        #expect(tracker.mouseMoved(toX: 600, windowWidth: 1000) == .forward)
        #expect(tracker.mouseMoved(toX: 100, windowWidth: 1000) == .leavePage)
        #expect(tracker.mouseMoved(toX: 150, windowWidth: 1000) == .ignore)
        #expect(tracker.isShielded)
        #expect(tracker.mouseMoved(toX: 600, windowWidth: 1000) == .forward)
        #expect(tracker.mouseMoved(toX: 100, windowWidth: 1000) == .leavePage)

        // Out of a window: nothing to cover.
        #expect(tracker.mouseMoved(toX: 100, windowWidth: nil) == .forward)

        // The sidebar hides with the mouse under it.
        _ = tracker.mouseMoved(toX: 100, windowWidth: 1000)
        tracker.shield = nil
        #expect(!tracker.isShielded)
        #expect(tracker.mouseMoved(toX: 100, windowWidth: 1000) == .forward)
    }
}
