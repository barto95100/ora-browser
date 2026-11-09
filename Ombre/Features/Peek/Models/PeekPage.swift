import AppKit
import Foundation

/// A link previewed over the current page (Peek, like Arc): its own page, in
/// the space and privacy mode of the tab it comes from, until it is closed or
/// opened as a tab (the page then moves to the tab as it is). It behaves like
/// a tab of that space: site permissions, dialogs, logins, file uploads.
@MainActor
final class PeekPage: ObservableObject, Identifiable {
    let id = UUID()
    let page: BrowserPage
    let isPrivate: Bool
    /// The tab Peek was opened from.
    let openerTabID: UUID
    /// The space of the tab Peek was opened from: its site permissions apply.
    let spaceID: UUID
    @Published private(set) var url: URL
    @Published private(set) var title: String = ""
    @Published private(set) var isLoading = true
    /// The page went to a tab: Peek must no longer show it (its view, still
    /// fading out, would take the page back from the tab).
    @Published private(set) var isMovedToTab = false
    /// A site permission the page waits for, asked in Peek.
    @Published private(set) var permissionRequest: SitePermissionRequest?
    /// Loads kept from the page (ads, trackers), by host: the tab gets them
    /// if Peek becomes one.
    private(set) var blockedContent: [String: Int] = [:]
    /// The page's dialogs and login sheets.
    let sheets = PageSheetPresenter()
    private let pageDelegate: PeekPageDelegate

    init(page: BrowserPage, url: URL, opener: Tab) {
        self.page = page
        self.url = url
        isPrivate = opener.isPrivate
        openerTabID = opener.id
        spaceID = opener.container.id
        pageDelegate = PeekPageDelegate(opener: opener)
        pageDelegate.peek = self
        page.delegate = pageDelegate
        page.load(URLRequest(url: url))
    }

    func moveToTab() {
        cancelPermissionRequest()
        isMovedToTab = true
    }

    /// Peek closes: what the page waits for is refused.
    func close() {
        cancelPermissionRequest()
        sheets.dismiss()
    }

    /// Shows a permission prompt in Peek; one waiting is denied first.
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
            spaceID: spaceID,
            isPrivate: isPrivate
        )
    }

    func cancelPermissionRequest() {
        guard let request = permissionRequest else { return }
        permissionRequest = nil
        request.resolve(granted: false)
    }

    fileprivate func update(url: URL?) {
        if let url, url != self.url { self.url = url }
    }

    fileprivate func update(title: String?) {
        let title = title ?? ""
        if title != self.title { self.title = title }
    }

    fileprivate func update(isLoading: Bool) {
        if isLoading != self.isLoading { self.isLoading = isLoading }
    }

    fileprivate func recordBlockedContent(from url: URL) {
        blockedContent[url.host ?? url.absoluteString, default: 0] += 1
    }

    /// A new page started loading: what the last one asked goes.
    fileprivate func navigationDidStart() {
        cancelPermissionRequest()
        if !blockedContent.isEmpty { blockedContent = [:] }
    }
}

/// Follows the Peek page; links it opens in new windows become tabs. Like a
/// tab's (`TabBrowserPageDelegate`) for permissions, dialogs and uploads.
private final class PeekPageDelegate: BrowserPageDelegate {
    weak var peek: PeekPage?
    private weak var opener: Tab?

    init(opener: Tab) {
        self.opener = opener
    }

    func browserPage(
        _ page: BrowserPage,
        decidePolicyFor navigationAction: BrowserNavigationAction
    ) -> BrowserNavigationActionDisposition {
        // ⌘-click: a background tab, like in a tab.
        guard navigationAction.modifierFlags.contains(.command), let url = navigationAction.request.url else {
            return .allow
        }
        openTab(url, inFront: navigationAction.modifierFlags.contains(.shift))
        return .cancel
    }

    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL, disposition: BrowserNewTabDisposition) {
        openTab(url, inFront: disposition != .background)
    }

    func browserPage(_ page: BrowserPage, didChangeURL url: URL?) {
        peek?.update(url: url)
    }

    func browserPage(_ page: BrowserPage, didChangeTitle title: String?) {
        peek?.update(title: title)
    }

    func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent) {
        peek?.update(isLoading: event.isLoading)
        switch event.phase {
        case .started: peek?.navigationDidStart()
        case .committed: peek?.sheets.dialogPolicy.pageDidCommitNewDocument()
        case .finished: break
        }
    }

    /// A load refused before it started (a restricted port): not loading.
    func browserPage(_ page: BrowserPage, didFailNavigationWith error: Error, failingURL: URL?) {
        peek?.update(isLoading: false)
    }

    func browserPage(_ page: BrowserPage, didStartDownload download: BrowserDownloadTask) {
        MainActor.assumeIsolated {
            opener?.downloadManager?.handleDownload(download)
        }
    }

    /// The opener's space protections, as in a tab: an exempted site isn't
    /// blocked (MOT-19).
    func browserPage(_ page: BrowserPage, allowsContentBlockingFor url: URL) -> Bool {
        guard let opener else { return true }
        return opener.areProtectionsEnabled(for: url)
    }

    func browserPage(_ page: BrowserPage, didBlockContentFrom url: URL) {
        peek?.recordBlockedContent(from: url)
    }

    func browserPage(
        _ page: BrowserPage,
        requestPermission permission: BrowserPermissionKind,
        origin: URL?,
        decisionHandler: @escaping (BrowserPermissionDecision) -> Void
    ) {
        guard let peek, isShown else {
            decisionHandler(.deny)
            return
        }
        SitePermissionGate.request(
            permission,
            origin: origin,
            spaceID: peek.spaceID,
            isPrivate: peek.isPrivate,
            present: { peek.presentPermissionRequest($0) },
            decisionHandler: decisionHandler
        )
    }

    func browserPage(
        _ page: BrowserPage,
        queryPermission permission: BrowserPermissionKind,
        origin: URL?
    ) -> BrowserPermissionDecision {
        guard let peek else { return .prompt }
        return SitePermissionGate.query(permission, origin: origin, spaceID: peek.spaceID, isPrivate: peek.isPrivate)
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
        guard let peek else {
            completion(.refused)
            return
        }
        peek.sheets.runJavaScriptDialog(dialog, in: page.window, isShown: isShown, completion: completion)
    }

    func browserPage(
        _ page: BrowserPage,
        authenticate request: HTTPAuthenticationRequest,
        completion: @escaping (URLCredential?) -> Void
    ) {
        guard let peek else {
            completion(nil)
            return
        }
        peek.sheets.authenticate(
            request,
            in: page.window,
            isShown: isShown,
            isPrivate: peek.isPrivate,
            completion: completion
        )
    }

    /// Peek is the one shown over its window's page (not one on its way to
    /// a tab).
    private var isShown: Bool {
        guard let peek, !peek.isMovedToTab, let tabManager = opener?.tabManager else { return false }
        return MainActor.assumeIsolated { tabManager.peek === peek }
    }

    /// Tracking parameters taken off links, as in a tab of the same space.
    func browserPage(_ page: BrowserPage, removesLinkTrackingFrom url: URL) -> Bool {
        guard let opener else { return false }
        return opener.privacySettings.blockThirdPartyTrackers && opener.areProtectionsEnabled(for: url)
    }

    private func openTab(_ url: URL, inFront: Bool) {
        guard let opener, let tabManager = opener.tabManager else { return }
        MainActor.assumeIsolated {
            _ = tabManager.openTab(
                url: url,
                historyManager: opener.historyManager ?? tabManager.historyManager,
                downloadManager: opener.downloadManager,
                focusAfterOpening: inFront,
                isPrivate: opener.isPrivate,
                loadSilently: !inFront
            )
        }
    }
}
