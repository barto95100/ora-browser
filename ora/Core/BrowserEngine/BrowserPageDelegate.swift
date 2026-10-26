import AppKit
import Foundation

protocol BrowserPageDelegate: AnyObject {
    func browserPage(
        _ page: BrowserPage,
        decidePolicyFor navigationAction: BrowserNavigationAction
    ) -> BrowserNavigationActionDisposition
    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL)
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

    func browserPage(_ page: BrowserPage, didRequestOpenInNewTab url: URL) {}

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

    func browserPage(_ page: BrowserPage, didChangeMediaCaptureState state: BrowserMediaCaptureState) {}

    func browserPageWebContentProcessDidTerminate(_ page: BrowserPage) {}
}
