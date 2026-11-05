import AppKit

/// The part of the window a floating panel (the sidebar) covers: the page
/// under it must not see the mouse (hover effects, cursor). Handled by the
/// web view itself, never in the page's DOM, where a page could see it (SEC-26).
struct MouseShield: Equatable {
    enum Edge: Equatable {
        case leading
        case trailing
    }

    let edge: Edge
    /// The sidebar's share of the window, clamped like the floating
    /// sidebar's (`FloatingSidebarOverlay`): the same width, never more.
    let fraction: CGFloat

    func covers(windowX: CGFloat, windowWidth: CGFloat) -> Bool {
        let minimum = SidebarLayout.minimumFraction(forWindowWidth: windowWidth)
        let width = windowWidth * min(max(fraction, minimum), SidebarLayout.maximumFraction)
        switch edge {
        case .leading: return windowX < width
        case .trailing: return windowX > windowWidth - width
        }
    }
}

/// What the web view does with a mouse move, given the shield.
struct MouseShieldTracker {
    enum Action: Equatable {
        /// To the page, as usual.
        case forward
        /// The mouse went under the panel: the page is told it left.
        case leavePage
        /// Still under the panel: the page sees nothing.
        case ignore
    }

    var shield: MouseShield? {
        didSet { if shield == nil { isShielded = false } }
    }

    private(set) var isShielded = false

    mutating func mouseMoved(toX windowX: CGFloat, windowWidth: CGFloat?) -> Action {
        guard let shield, let windowWidth, shield.covers(windowX: windowX, windowWidth: windowWidth) else {
            isShielded = false
            return .forward
        }
        guard !isShielded else { return .ignore }
        isShielded = true
        return .leavePage
    }

    func isCovered(windowX: CGFloat, windowWidth: CGFloat?) -> Bool {
        guard let shield, let windowWidth else { return false }
        return shield.covers(windowX: windowX, windowWidth: windowWidth)
    }
}
