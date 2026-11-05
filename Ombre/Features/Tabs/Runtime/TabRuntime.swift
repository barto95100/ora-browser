import Foundation
import Observation

/// What a tab's page is doing in one window, apart from the saved tab (ONG-05):
/// owned by the window's `TabManager`, so two windows showing the same tab
/// never share it, and never lost when the database hands out the tab again.
/// It takes over `Tab`'s transient state one part at a time. Observable like
/// the tab's own properties: a view reading it, even through `Tab`, redraws
/// when what it read changes, and only then.
@MainActor
@Observable
final class TabRuntime {
    /// A page that could not load (or crashed): its error page.
    struct NavigationFailure {
        let error: Error
        /// The address that failed, to retry it.
        let url: URL?
    }

    /// The tab's page and its delegate, while it is loaded in this window.
    var page: BrowserPage?
    var pageDelegate: TabBrowserPageDelegate?
    /// The page is in place and asked to load: shown instead of a blank view.
    var isPageReady = false
    var isLoading = false

    /// Reloading a page whose process ended (see `Tab+CrashRecovery`).
    var crashRecovery = PageCrashRecoveryPolicy()
    var isReloadingAfterCrash = false
    var showsCrashRecoveryNotice = false

    private(set) var navigationFailure: NavigationFailure?
    /// The link under the mouse, shown at the bottom of the page.
    private(set) var hoveredLinkURL: String?

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

    /// Changes only a different link: every change redraws the page's overlays.
    func setHoveredLink(_ link: String?) {
        let link = link?.isEmpty == true ? nil : link
        if hoveredLinkURL != link { hoveredLinkURL = link }
    }
}
