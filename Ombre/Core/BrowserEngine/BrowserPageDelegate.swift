import AppKit
import Foundation
@preconcurrency import WebKit

@MainActor
protocol BrowserPageDelegate: AnyObject {
    func browserPage(
        _ page: BrowserPage,
        decidePolicyFor navigationAction: BrowserNavigationAction
    ) -> BrowserNavigationActionDisposition
    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL, disposition: BrowserNewTabDisposition)
    /// The user clicked a link that opens a new window (`target="_blank"`):
    /// true if the delegate opened it itself (Peek), else it opens in a new tab.
    func browserPage(_ page: BrowserPage, opensNewWindowLink url: URL, modifierFlags: NSEvent.ModifierFlags) -> Bool
    /// The page opens a window that isn't a popup (`window.open(url)`, a
    /// `target="_blank"` link): the web view of a tab linked to it, made with
    /// WebKit's `configuration`, which WebKit then loads; nil for a tab of
    /// its own, not linked.
    func browserPage(
        _ page: BrowserPage,
        linkedPageWith configuration: WKWebViewConfiguration,
        for url: URL?,
        disposition: BrowserNewTabDisposition
    ) -> WKWebView?
    /// The page opens a popup (`window.open` with a size, see
    /// `BrowserPopupWindow`): the web view of its page, made with WebKit's
    /// `configuration` in the page's space; nil refuses it.
    func browserPage(
        _ page: BrowserPage,
        openPopupWith configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures,
        openerOrigin: URL?
    ) -> WKWebView?
    /// The page closed itself (`window.close()`).
    func browserPageDidClose(_ page: BrowserPage)
    func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent)
    /// The page's address changed, including same-page navigations.
    func browserPage(_ page: BrowserPage, didChangeURL url: URL?)
    /// Items the app adds at the end of the page's context menu.
    @MainActor func browserPageContextMenuItems(_ page: BrowserPage) -> [NSMenuItem]
    func browserPage(_ page: BrowserPage, didChangeTitle title: String?)
    func browserPage(_ page: BrowserPage, didFailNavigationWith error: Error, failingURL: URL?)
    func browserPage(_ page: BrowserPage, didReceiveScriptMessage message: BrowserScriptMessage)
    func browserPage(
        _ page: BrowserPage,
        requestPermission permission: BrowserPermissionKind,
        origin: URL?,
        decisionHandler: @escaping (BrowserPermissionDecision) -> Void
    )
    /// Answer to `navigator.permissions.query()` for a capture permission,
    /// without asking the user.
    func browserPage(
        _ page: BrowserPage,
        queryPermission permission: BrowserPermissionKind,
        origin: URL?
    ) -> BrowserPermissionDecision
    func browserPage(
        _ page: BrowserPage,
        runOpenPanelWith options: BrowserOpenPanelOptions,
        completion: @escaping ([URL]?) -> Void
    )
    /// `alert`, `confirm` or `prompt`: `completion` must be called, once.
    func browserPage(
        _ page: BrowserPage,
        runJavaScriptDialog dialog: BrowserJavaScriptDialog,
        completion: @escaping (BrowserJavaScriptDialogReply) -> Void
    )
    func browserPage(_ page: BrowserPage, didStartDownload download: BrowserDownloadTask)
    /// Whether the space's content rules apply to this site (not exempted).
    func browserPage(_ page: BrowserPage, allowsContentBlockingFor url: URL) -> Bool
    /// A content rule kept a load from the page (ad, tracker).
    func browserPage(_ page: BrowserPage, didBlockContentFrom url: URL)
    /// Whether tracking parameters are taken off this address before it loads
    /// (see `LinkTrackingProtection`).
    func browserPage(_ page: BrowserPage, removesLinkTrackingFrom url: URL) -> Bool
    /// A page of a site allowed to send notifications shows one.
    func browserPage(_ page: BrowserPage, showNotification notification: BrowserWebNotification)
    /// The page closed one of its notifications (`notification.close()`).
    func browserPage(_ page: BrowserPage, closeNotification id: String)
    func browserPage(_ page: BrowserPage, didChangeMediaCaptureState state: BrowserMediaCaptureState)
    /// The process rendering the page ended (crash, or macOS reclaiming memory).
    /// The page is blank until it is reloaded.
    func browserPageWebContentProcessDidTerminate(_ page: BrowserPage)
    /// The page's theme color (`<meta name="theme-color">`) changed; nil when
    /// it declares none.
    func browserPage(_ page: BrowserPage, didChangeThemeColor color: NSColor?)
    /// The server asks for a name and password: `completion` gets them, or
    /// nil (the page shows the server's refusal). Called once each.
    func browserPage(
        _ page: BrowserPage,
        authenticate request: HTTPAuthenticationRequest,
        completion: @escaping (URLCredential?) -> Void
    )
}

extension BrowserPageDelegate {
    @MainActor func browserPageContextMenuItems(_ page: BrowserPage) -> [NSMenuItem] {
        []
    }

    func browserPage(
        _ page: BrowserPage,
        decidePolicyFor navigationAction: BrowserNavigationAction
    ) -> BrowserNavigationActionDisposition {
        .allow
    }

    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL, disposition: BrowserNewTabDisposition) {}

    func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent) {}

    func browserPage(
        _ page: BrowserPage,
        openPopupWith configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures,
        openerOrigin: URL?
    ) -> WKWebView? {
        nil
    }

    func browserPageDidClose(_ page: BrowserPage) {}

    func browserPage(_ page: BrowserPage, didChangeURL url: URL?) {}

    func browserPage(_ page: BrowserPage, didChangeThemeColor color: NSColor?) {}
    func browserPage(_ page: BrowserPage, opensNewWindowLink url: URL, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        false
    }

    func browserPage(
        _ page: BrowserPage,
        linkedPageWith configuration: WKWebViewConfiguration,
        for url: URL?,
        disposition: BrowserNewTabDisposition
    ) -> WKWebView? {
        nil
    }
    func browserPage(
        _ page: BrowserPage,
        authenticate request: HTTPAuthenticationRequest,
        completion: @escaping (URLCredential?) -> Void
    ) {
        completion(nil)
    }

    func browserPage(_ page: BrowserPage, didChangeTitle title: String?) {}

    func browserPage(_ page: BrowserPage, didFailNavigationWith error: Error, failingURL: URL?) {}

    func browserPage(_ page: BrowserPage, didReceiveScriptMessage message: BrowserScriptMessage) {}

    func browserPage(
        _ page: BrowserPage,
        requestPermission permission: BrowserPermissionKind,
        origin: URL?,
        decisionHandler: @escaping (BrowserPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }

    func browserPage(
        _ page: BrowserPage,
        queryPermission permission: BrowserPermissionKind,
        origin: URL?
    ) -> BrowserPermissionDecision {
        .prompt
    }

    func browserPage(
        _ page: BrowserPage,
        runOpenPanelWith options: BrowserOpenPanelOptions,
        completion: @escaping ([URL]?) -> Void
    ) {
        completion(nil)
    }

    func browserPage(
        _ page: BrowserPage,
        runJavaScriptDialog dialog: BrowserJavaScriptDialog,
        completion: @escaping (BrowserJavaScriptDialogReply) -> Void
    ) {
        completion(.refused)
    }

    func browserPage(_ page: BrowserPage, didStartDownload download: BrowserDownloadTask) {}

    func browserPage(_ page: BrowserPage, allowsContentBlockingFor url: URL) -> Bool {
        true
    }

    func browserPage(_ page: BrowserPage, didBlockContentFrom url: URL) {}

    func browserPage(_ page: BrowserPage, removesLinkTrackingFrom url: URL) -> Bool {
        false
    }

    func browserPage(_ page: BrowserPage, showNotification notification: BrowserWebNotification) {}

    func browserPage(_ page: BrowserPage, closeNotification id: String) {}

    func browserPage(_ page: BrowserPage, didChangeMediaCaptureState state: BrowserMediaCaptureState) {}

    func browserPageWebContentProcessDidTerminate(_ page: BrowserPage) {}
}
