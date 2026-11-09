import AppKit
import Combine
@preconcurrency import WebKit

/// Where a popup belongs: the space and privacy mode of the tab that opened
/// it (or of the page that opened the popup that opened it), and where its
/// downloads go. Kept by value: the popup outlives a closed tab.
@MainActor
struct PopupContext {
    let spaceID: UUID
    let isPrivate: Bool
    let privateSession: UUID?
    let downloadManager: DownloadManager?

    init(spaceID: UUID, isPrivate: Bool, privateSession: UUID?, downloadManager: DownloadManager?) {
        self.spaceID = spaceID
        self.isPrivate = isPrivate
        self.privateSession = privateSession
        self.downloadManager = downloadManager
    }

    init(tab: Tab) {
        self.init(
            spaceID: tab.container.id,
            isPrivate: tab.isPrivate,
            privateSession: tab.tabManager?.privateSessionID,
            downloadManager: tab.downloadManager ?? tab.tabManager?.downloadManager
        )
    }
}

/// A popup's page (`window.open` with a size), like a tab of its space: its
/// own scripts and protections, site permissions asked in the popup, dialogs
/// and logins as sheets, file uploads, downloads.
@MainActor
final class PopupPage: ObservableObject {
    let page: BrowserPage
    let context: PopupContext
    /// A site permission the page waits for, asked in the popup.
    @Published private(set) var permissionRequest: SitePermissionRequest?
    /// The page's dialogs and login sheets.
    let sheets = PageSheetPresenter()
    /// Closes the popup's window (`window.close()`, a popup only opened for a
    /// file).
    var closeWindow: (() -> Void)?
    /// The page's address or title changed (the window's title follows).
    var pageDidChange: (() -> Void)?
    private let pageDelegate: PopupPageDelegate

    /// Made with WebKit's `configuration` (required: it shares its opener's
    /// process and data), linked to `opener`.
    init(configuration: WKWebViewConfiguration, opener: BrowserPage?, context: PopupContext) {
        self.context = context
        page = Tab.makeLinkedBrowserPage(
            configuration: configuration,
            opener: opener,
            spaceID: context.spaceID,
            isPrivate: context.isPrivate,
            privateSession: context.privateSession
        )
        pageDelegate = PopupPageDelegate()
        pageDelegate.popup = self
        page.delegate = pageDelegate
    }

    /// The popup closes: what the page waits for is refused.
    func close() {
        cancelPermissionRequest()
        sheets.dismiss()
        page.teardown()
    }

    func presentPermissionRequest(_ request: SitePermissionRequest) {
        permissionRequest?.resolve(granted: false)
        permissionRequest = request
    }

    func answerPermissionRequest(granted: Bool, remember: Bool) {
        guard let request = permissionRequest else { return }
        permissionRequest = nil
        SitePermissionGate.answer(
            request,
            granted: granted,
            remember: remember,
            spaceID: context.spaceID,
            isPrivate: context.isPrivate
        )
    }

    func cancelPermissionRequest() {
        guard let request = permissionRequest else { return }
        permissionRequest = nil
        request.resolve(granted: false)
    }

    /// Whether the space's protections apply to this site (not exempted).
    func areProtectionsEnabled(for url: URL) -> Bool {
        guard let site = WebSite.registrableDomain(of: url) else { return true }
        return !SettingsStore.shared.privacySettings(for: context.spaceID).exemptSites.contains(site)
    }
}

/// Follows a popup's page, like a tab's delegate (`TabBrowserPageDelegate`).
private final class PopupPageDelegate: BrowserPageDelegate {
    weak var popup: PopupPage?

    /// In front: its window is on screen.
    private func isShown(_ page: BrowserPage) -> Bool {
        page.window?.isVisible ?? false
    }

    func browserPage(_ page: BrowserPage, didChangeURL url: URL?) {
        popup?.pageDidChange?()
    }

    func browserPage(_ page: BrowserPage, didChangeTitle title: String?) {
        popup?.pageDidChange?()
    }

    func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent) {
        switch event.phase {
        case .started: popup?.cancelPermissionRequest()
        case .committed: popup?.sheets.dialogPolicy.pageDidCommitNewDocument()
        case .finished: break
        }
    }

    /// A popup opening a popup: in the same space.
    func browserPage(
        _ page: BrowserPage,
        openPopupWith configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures,
        openerOrigin: URL?
    ) -> WKWebView? {
        guard let popup else { return nil }
        return BrowserPopupWindow.open(
            configuration: configuration,
            windowFeatures: windowFeatures,
            openerWindow: page.window,
            opener: page,
            openerOrigin: openerOrigin,
            context: popup.context
        )
    }

    /// Any other window the popup opens (`target="_blank"`, `window.open`
    /// without a size): another popup window, as before.
    func browserPage(
        _ page: BrowserPage,
        linkedPageWith configuration: WKWebViewConfiguration,
        for url: URL?,
        disposition: BrowserNewTabDisposition
    ) -> WKWebView? {
        browserPage(page, openPopupWith: configuration, windowFeatures: WKWindowFeatures(), openerOrigin: nil)
    }

    /// `window.close()` from the popup.
    func browserPageDidClose(_ page: BrowserPage) {
        popup?.closeWindow?()
    }

    func browserPage(
        _ page: BrowserPage,
        requestPermission permission: BrowserPermissionKind,
        origin: URL?,
        decisionHandler: @escaping (BrowserPermissionDecision) -> Void
    ) {
        // No notifications from a popup: it goes once its task is done, and
        // a click would lead nowhere.
        guard let popup, isShown(page), permission != .notifications else {
            decisionHandler(.deny)
            return
        }
        SitePermissionGate.request(
            permission,
            origin: origin,
            spaceID: popup.context.spaceID,
            isPrivate: popup.context.isPrivate,
            present: { popup.presentPermissionRequest($0) },
            decisionHandler: decisionHandler
        )
    }

    func browserPage(
        _ page: BrowserPage,
        queryPermission permission: BrowserPermissionKind,
        origin: URL?
    ) -> BrowserPermissionDecision {
        guard let popup else { return .prompt }
        return SitePermissionGate.query(
            permission,
            origin: origin,
            spaceID: popup.context.spaceID,
            isPrivate: popup.context.isPrivate
        )
    }

    func browserPage(
        _ page: BrowserPage,
        runOpenPanelWith options: BrowserOpenPanelOptions,
        completion: @escaping ([URL]?) -> Void
    ) {
        BrowserOpenPanel.run(options, completion: completion)
    }

    func browserPage(
        _ page: BrowserPage,
        runJavaScriptDialog dialog: BrowserJavaScriptDialog,
        completion: @escaping (BrowserJavaScriptDialogReply) -> Void
    ) {
        guard let popup else {
            completion(.refused)
            return
        }
        popup.sheets.runJavaScriptDialog(dialog, in: page.window, isShown: isShown(page), completion: completion)
    }

    func browserPage(
        _ page: BrowserPage,
        authenticate request: HTTPAuthenticationRequest,
        completion: @escaping (URLCredential?) -> Void
    ) {
        guard let popup else {
            completion(nil)
            return
        }
        popup.sheets.authenticate(
            request,
            in: page.window,
            isShown: isShown(page),
            isPrivate: popup.context.isPrivate,
            completion: completion
        )
    }

    /// To the downloads of the tab's window, even once that tab is closed.
    /// A popup only opened for the file then closes, like such a tab.
    func browserPage(_ page: BrowserPage, didStartDownload download: BrowserDownloadTask) {
        guard let popup, let downloadManager = popup.context.downloadManager else {
            download.cancel()
            return
        }
        downloadManager.handleDownload(download)
        if TabBrowserPageDelegate.closesTab(
            afterDownloadNavigation: page.isDownloadNavigation,
            shown: page.lastCommittedURL
        ) {
            popup.closeWindow?()
        }
    }

    func browserPage(_ page: BrowserPage, allowsContentBlockingFor url: URL) -> Bool {
        popup?.areProtectionsEnabled(for: url) ?? true
    }

    func browserPage(_ page: BrowserPage, removesLinkTrackingFrom url: URL) -> Bool {
        guard let popup else { return false }
        return SettingsStore.shared.privacySettings(for: popup.context.spaceID).blockThirdPartyTrackers
            && popup.areProtectionsEnabled(for: url)
    }
}
