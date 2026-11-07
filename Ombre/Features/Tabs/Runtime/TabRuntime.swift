import Foundation
import Observation
import Translation

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

    /// The page's language, once read after it loaded (see `Tab+Translation`).
    var pageLanguage: Locale.Language?
    /// Whether the page shows translated (see `Tab+Translation`).
    var translation: PageTranslationState = .original
    /// The translation panel, shown over the page.
    var showsTranslationPanel = false
    /// A translation waiting for a session from the page's view (see
    /// `PageTranslationHost`): to download a language, or before macOS 26.
    var translationRequest: PageTranslationRequest?
    /// The running translation: a later one, or the page going, ends it.
    @ObservationIgnored var translationRunID: UUID?
    @ObservationIgnored var translationTask: Task<Void, Never>?
    @ObservationIgnored private var translationRequestCount = 0
    /// The page's translations already made (see `PageTranslationMemory`).
    @ObservationIgnored var translationMemory: PageTranslationMemory?
    /// The tab's translation session, kept for its languages while its page
    /// lives: a new one loads macOS's model again (macOS 26).
    @ObservationIgnored var translationSession: (pair: PageTranslationPair, session: TranslationSession)?

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
        resetTranslation()
        translationSession = nil
    }

    /// A new document: its language is read again once loaded, and a
    /// translation of the previous one stops.
    func resetTranslation() {
        stopTranslation()
        translationMemory = nil
        pageLanguage = nil
        if translation != .original { translation = .original }
        if showsTranslationPanel { showsTranslationPanel = false }
    }

    /// Asks the page's view for a session (see `PageTranslationHost`). Each
    /// request differs from the one before, even for the same languages, so
    /// the view's task always starts again.
    func requestTranslationSession(id: UUID, pair: PageTranslationPair, needsDownload: Bool) {
        translationRequestCount += 1
        translationRequest = PageTranslationRequest(
            id: id, pair: pair, needsDownload: needsDownload, version: translationRequestCount % 2
        )
    }

    /// The memory of the page's translations into `pair` (a new one for other
    /// languages).
    func translationMemory(for pair: PageTranslationPair) -> PageTranslationMemory {
        if let memory = translationMemory, memory.pair == pair { return memory }
        let memory = PageTranslationMemory(pair: pair)
        translationMemory = memory
        return memory
    }

    /// Ends the running translation, if any: its late results are dropped.
    func stopTranslation() {
        translationRunID = nil
        translationTask?.cancel()
        translationTask = nil
        if translationRequest != nil { translationRequest = nil }
    }

    /// Changes only a different link: every change redraws the page's overlays.
    func setHoveredLink(_ link: String?) {
        let link = link?.isEmpty == true ? nil : link
        if hoveredLinkURL != link { hoveredLinkURL = link }
    }
}
