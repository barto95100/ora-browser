import AppKit
import Foundation
@preconcurrency import WebKit

extension BrowserPage: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Links the site marks as downloads (`<a download>`): download instead
        // of navigating. Continues in webView(_:navigationAction:didBecome:).
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        let action = BrowserNavigationAction(
            request: navigationAction.request,
            modifierFlags: navigationAction.modifierFlags
        )

        switch delegate?.browserPage(self, decidePolicyFor: action) ?? .allow {
        case .allow:
            if let upgraded = httpsURL(for: navigationAction) {
                decisionHandler(.cancel)
                var request = navigationAction.request
                request.url = upgraded
                webView.load(request)
                return
            }
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
        case .openInNewTab:
            if let url = navigationAction.request.url {
                delegate?.browserPage(self, didRequestOpenInNewTab: url)
            }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if !isDownloadNavigation {
            originalURL = lastCommittedURL
            emitNavigationEvent(
                phase: .started,
                url: webView.url,
                title: webView.title,
                progress: 10.0,
                isLoading: true
            )
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        httpsUpgrade.navigationCommitted()
        if !isDownloadNavigation {
            lastCommittedURL = webView.url
            emitNavigationEvent(
                phase: .committed,
                url: webView.url,
                title: webView.title,
                progress: webView.estimatedProgress * 100.0,
                isLoading: true
            )
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !isDownloadNavigation {
            lastCommittedURL = webView.url
            emitNavigationEvent(
                phase: .finished,
                url: webView.url,
                title: webView.title,
                progress: webView.estimatedProgress * 100.0,
                isLoading: false
            )
            originalURL = nil
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        originalURL = nil
        delegate?.browserPageWebContentProcessDidTerminate(self)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !isDownloadNavigation else {
            originalURL = nil
            return
        }
        // Handled as a whole by webViewWebContentProcessDidTerminate(_:).
        guard !isWebContentProcessTerminationError(error) else { return }

        emitNavigationEvent(
            phase: .finished,
            url: webView.url,
            title: webView.title,
            progress: 100.0,
            isLoading: false
        )

        if !handleCancelledNavigationError(error) {
            delegate?.browserPage(self, didFailNavigationWith: error, failingURL: webView.url)
        }
        originalURL = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !isDownloadNavigation else {
            originalURL = nil
            return
        }
        // Handled as a whole by webViewWebContentProcessDidTerminate(_:).
        guard !isWebContentProcessTerminationError(error) else { return }

        let nsError = error as NSError
        let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? webView.url
        // The site does not answer over HTTPS: load the HTTP page asked for,
        // without showing an error.
        if let fallback = httpsUpgrade.fallback(afterFailing: failingURL, error: error) {
            webView.load(URLRequest(url: fallback))
            return
        }

        emitNavigationEvent(
            phase: .finished,
            url: webView.url,
            title: webView.title,
            progress: 100.0,
            isLoading: false
        )

        if handleCancelledNavigationError(error) {
            return
        }

        delegate?.browserPage(self, didFailNavigationWith: error, failingURL: failingURL)
        originalURL = nil
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust,
           sslBypassedHosts.contains(challenge.protectionSpace.host)
        {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    @available(macOS 11.3, *)
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.canShowMIMEType {
            isDownloadNavigation = false
            originalURL = nil
            decisionHandler(.allow)
            return
        }

        isDownloadNavigation = true
        emitNavigationEvent(
            phase: .finished,
            url: originalURL,
            title: webView.title,
            progress: 0,
            isLoading: false
        )
        decisionHandler(.download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        guard let downloadURL = navigationAction.request.url else { return }
        delegate?.browserPage(self, didStartDownload: BrowserDownloadTask(download: download, originalURL: downloadURL))
    }

    /// "Download Image", "Download Linked File" and "Download Video" from the
    /// page's context menu. Private WebKit delegate method
    /// (WKNavigationDelegatePrivate, macOS 12+): without it, WebKit creates the
    /// download but nothing takes care of it, so it never starts.
    @objc(_webView:contextMenuDidCreateDownload:)
    func webView(_ webView: WKWebView, contextMenuDidCreate download: WKDownload) {
        guard let downloadURL = download.originalRequest?.url else { return }
        delegate?.browserPage(self, didStartDownload: BrowserDownloadTask(download: download, originalURL: downloadURL))
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        guard let downloadURL = navigationResponse.response.url else { return }
        let task = BrowserDownloadTask(download: download, originalURL: downloadURL)
        delegate?.browserPage(self, didStartDownload: task)
        isDownloadNavigation = false
        originalURL = nil
    }

    // MARK: - Helpers

    /// The HTTPS address to load instead, for a page loaded in this tab (not
    /// back/forward or reload, which must keep their history entry).
    private func httpsURL(for navigationAction: WKNavigationAction) -> URL? {
        guard navigationAction.targetFrame?.isMainFrame == true,
              navigationAction.navigationType != .backForward,
              navigationAction.navigationType != .reload,
              let url = navigationAction.request.url
        else { return nil }
        return httpsUpgrade.upgrade(url, httpMethod: navigationAction.request.httpMethod)
    }

    private func emitNavigationEvent(
        phase: BrowserNavigationPhase,
        url: URL?,
        title: String?,
        progress: Double,
        isLoading: Bool
    ) {
        delegate?.browserPage(
            self,
            didUpdateNavigation: BrowserNavigationEvent(
                phase: phase,
                url: url,
                title: title,
                progress: progress,
                isLoading: isLoading
            )
        )
    }

    private func handleCancelledNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    /// Navigation failure caused by the end of the web content process, which is
    /// reported separately by `webViewWebContentProcessDidTerminate(_:)`.
    private func isWebContentProcessTerminationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == WKError.errorDomain
            && nsError.code == WKError.Code.webContentProcessTerminated.rawValue
    }
}
