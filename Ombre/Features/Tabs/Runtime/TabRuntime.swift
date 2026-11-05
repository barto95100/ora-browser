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

    /// Passwords: filling the page's forms, and what it shows over the page.
    var passwordCoordinator: PasswordAutofillCoordinator?
    var passwordOverlayState: PasswordAutofillOverlayState?
    var passwordTriggerOverlayState: PasswordAutofillOverlayState?
    /// Permission prompt shown for the page (see `Tab+SitePermissions`).
    var permissionRequest: SitePermissionRequest?
    /// Camera and microphone in use by the page.
    var mediaCaptureState = BrowserMediaCaptureState()
    /// Site the shown favicon belongs to (see `Tab+Favicon.swift`).
    var faviconSiteHost: String?
    /// Last page recorded in the history (see `Tab+History.swift`).
    var lastRecordedVisitURL: URL?
    /// Local file the tab has sandbox access to (see `Tab+LocalFile.swift`).
    var fileAccessURL: URL?
    /// Folder of a local page whose images and styles are blocked, offered to
    /// the user (see `Tab+LocalFile.swift`).
    var folderAccessRequest: URL?
    /// Loads kept from the page by content rules, by host (see `Tab+Protections.swift`).
    var blockedContent: [String: Int] = [:]

    /// Translating the page into the Mac's language (see `Tab+Translation`).
    var translation: PageTranslationState = .unavailable

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
        translation = .unavailable
    }

    /// Changes only a different link: every change redraws the page's overlays.
    func setHoveredLink(_ link: String?) {
        let link = link?.isEmpty == true ? nil : link
        if hoveredLinkURL != link { hoveredLinkURL = link }
    }
}
