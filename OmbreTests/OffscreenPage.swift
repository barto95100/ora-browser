import Foundation
@testable import Ombre
import WebKit

/// A page in a hidden web view, never in a window.
@MainActor
final class OffscreenPage: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?

    /// `ruleList`: content rules applied from the first load; `baseURL`:
    /// the page's address (its site, for the rules).
    init(_ body: String, ruleList: WKContentRuleList? = nil, baseURL: URL? = nil) async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let ruleList { configuration.userContentController.add(ruleList) }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        await withCheckedContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString("<!doctype html><html><body>\(body)</body></html>", baseURL: baseURL)
        }
    }

    func run(_ body: String) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            ElementPickerScript.source + "\nconst picker = window.__ombrePicker;\n" + body,
            contentWorld: ElementPickerScript.world
        )
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            loaded?.resume()
            loaded = nil
        }
    }
}
