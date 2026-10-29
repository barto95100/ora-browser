import AppKit
import Foundation

protocol BrowserPageDelegate: AnyObject {
    func browserPage(
        _ page: BrowserPage,
        decidePolicyFor navigationAction: BrowserNavigationAction
    ) -> BrowserNavigationActionDisposition
    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL, disposition: BrowserNewTabDisposition)
    func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent)
    /// The page's address changed, including same-page navigations.
    func browserPage(_ page: BrowserPage, didChangeURL url: URL?)
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
    func browserPage(_ page: BrowserPage, runJavaScriptAlert message: String)
    func browserPage(_ page: BrowserPage, runJavaScriptConfirm message: String, completion: @escaping (Bool) -> Void)
    func browserPage(
        _ page: BrowserPage,
        runJavaScriptPrompt prompt: String,
        defaultText: String?,
        completion: @escaping (String?) -> Void
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
}

extension BrowserPageDelegate {
    func browserPage(
        _ page: BrowserPage,
        decidePolicyFor navigationAction: BrowserNavigationAction
    ) -> BrowserNavigationActionDisposition {
        .allow
    }

    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL, disposition: BrowserNewTabDisposition) {}

    func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent) {}

    func browserPage(_ page: BrowserPage, didChangeURL url: URL?) {}

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

    func browserPage(_ page: BrowserPage, runJavaScriptAlert message: String) {}

    func browserPage(_ page: BrowserPage, runJavaScriptConfirm message: String, completion: @escaping (Bool) -> Void) {
        completion(false)
    }

    func browserPage(
        _ page: BrowserPage,
        runJavaScriptPrompt prompt: String,
        defaultText: String?,
        completion: @escaping (String?) -> Void
    ) {
        completion(nil)
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
