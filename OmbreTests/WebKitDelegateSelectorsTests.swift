import Foundation
@testable import Ombre
import Testing

/// WebKit calls a delegate method only if its Objective-C selector exists:
/// a Swift signature that no longer matches WebKit's (a completion handler's
/// isolation, a label) only warns and is never called. These are the
/// methods with handlers, the ones such a change hits.
struct WebKitDelegateSelectorsTests {
    private static let pageSelectors = [
        "webView:decidePolicyForNavigationAction:decisionHandler:",
        "webView:decidePolicyForNavigationResponse:decisionHandler:",
        "webView:didReceiveAuthenticationChallenge:completionHandler:",
        "webView:requestMediaCapturePermissionForOrigin:initiatedByFrame:type:decisionHandler:",
        "webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:",
        "webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
        "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
        "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:"
    ]

    private static let popupSelectors = [
        "webView:decidePolicyForNavigationResponse:decisionHandler:",
        "webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:",
        "webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:",
        "webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:completionHandler:"
    ]

    @Test(arguments: pageSelectors)
    func pageAnswers(_ selector: String) {
        #expect(BrowserPage.instancesRespond(to: NSSelectorFromString(selector)))
    }

    @Test(arguments: popupSelectors)
    func popupAnswers(_ selector: String) {
        #expect(BrowserPopupWindow.instancesRespond(to: NSSelectorFromString(selector)))
    }

    /// Optional: without it, a redirected download keeps its first address.
    @Test func downloadFollowsRedirects() {
        let selector = "download:willPerformHTTPRedirection:newRequest:decisionHandler:"
        #expect(BrowserDownloadTask.instancesRespond(to: NSSelectorFromString(selector)))
    }
}
