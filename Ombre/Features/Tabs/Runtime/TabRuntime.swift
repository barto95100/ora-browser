import Foundation

/// What a tab's page is doing in one window, apart from the saved tab (ONG-05):
/// owned by the window's `TabManager`, so two windows showing the same tab
/// never share it, and never lost when the database hands out the tab again.
/// It takes over `Tab`'s transient state one part at a time.
@MainActor
final class TabRuntime: ObservableObject {
    /// A page that could not load (or crashed): its error page.
    struct NavigationFailure {
        let error: Error
        /// The address that failed, to retry it.
        let url: URL?
    }

    @Published private(set) var navigationFailure: NavigationFailure?
    /// The link under the mouse, shown at the bottom of the page.
    @Published private(set) var hoveredLinkURL: String?

    func navigationFailed(_ error: Error, url: URL?) {
        navigationFailure = NavigationFailure(error: error, url: url)
    }

    func clearNavigationFailure() {
        if navigationFailure != nil { navigationFailure = nil }
    }

    /// The page went (unloaded, rebuilt): nothing of it is left to show.
    func reset() {
        clearNavigationFailure()
        setHoveredLink(nil)
    }

    /// Publishes only a change: every publish redraws the page's overlays.
    func setHoveredLink(_ link: String?) {
        let link = link?.isEmpty == true ? nil : link
        if hoveredLinkURL != link { hoveredLinkURL = link }
    }
}
