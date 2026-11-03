import CoreGraphics

/// Width limits of the sidebar, docked or floating.
///
/// The minimum is a width in points rather than a share of the window, like
/// Safari or Arc: a share made the sidebar's narrowest width grow with the
/// window (about 290 pt on a large display).
enum SidebarLayout {
    /// Narrowest sidebar: the window buttons, the sidebar button and the tools
    /// menu, favorites (3 columns), tab rows, and the bottom bar (settings,
    /// spaces, new space) still fit; at 140 pt the bottom bar was cut.
    static let minimumWidth: CGFloat = 200

    /// Widest sidebar, as a share of the window.
    static let maximumFraction: CGFloat = 0.30

    /// Share of the window the minimum width represents, never above the maximum.
    static func minimumFraction(forWindowWidth windowWidth: CGFloat) -> CGFloat {
        guard windowWidth > 0 else { return maximumFraction }
        return min(minimumWidth / windowWidth, maximumFraction)
    }
}
