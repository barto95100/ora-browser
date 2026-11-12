import AppKit
import Foundation
@preconcurrency import WebKit

extension BrowserPage: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        // Links the site marks as downloads (`<a download>`): downloaded by the
        // page itself (its cookies, so a signed-in site works). Answering
        // `.download` relied on WebKit calling
        // webView(_:navigationAction:didBecome:), which it did not: the click
        // did nothing.
        if navigationAction.shouldPerformDownload {
            decisionHandler(.cancel)
            let request = navigationAction.request
            webView.startDownload(using: request) { [weak self] download in
                guard let self, let url = request.url else { return }
                let task = BrowserDownloadTask(download: download, originalURL: url)
                self.delegate?.browserPage(self, didStartDownload: task)
            }
            return
        }

        // A website from an extension's page (a link on its options page):
        // in a tab of its own, with the space's data and protections.
        if isExtensionPage, navigationAction.targetFrame?.isMainFrame ?? true,
           let url = navigationAction.request.url, url.scheme != webView.url?.scheme,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        {
            decisionHandler(.cancel)
            delegate?.browserPage(self, didRequestOpenInNewTab: url, disposition: .foreground)
            return
        }

        let action = BrowserNavigationAction(
            request: navigationAction.request,
            modifierFlags: navigationAction.modifierFlags,
            isMainFrameLinkClick: navigationAction.navigationType == .linkActivated
                && navigationAction.targetFrame?.isMainFrame == true
        )

        switch delegate?.browserPage(self, decidePolicyFor: action) ?? .allow {
        case .allow:
            // A page on a port browsers never open: WebKit would show a blank
            // page without a word; an error page says why, like Safari. Here,
            // once the app kept the link in this page (not a new tab, Peek).
            if navigationAction.targetFrame?.isMainFrame ?? true, let url = navigationAction.request.url,
               RestrictedPort.isRestricted(url)
            {
                decisionHandler(.cancel)
                delegate?.browserPage(self, didFailNavigationWith: RestrictedPort.error(for: url), failingURL: url)
                return
            }
            // A site exempted from protections loads without content rules.
            if navigationAction.targetFrame?.isMainFrame ?? true, let url = navigationAction.request.url {
                setContentBlocking(enabled: delegate?.browserPage(self, allowsContentBlockingFor: url) ?? true)
            }
            // Link Tracking Protection: the address loads without its
            // tracking parameters.
            if let cleaned = linkTrackingCleanedURL(for: navigationAction) {
                decisionHandler(.cancel)
                var request = navigationAction.request
                request.url = cleaned
                webView.load(request)
                return
            }
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
                delegate?.browserPage(self, didRequestOpenInNewTab: url, disposition: .foreground)
            }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        hasProvisionalNavigation = true
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
        hasProvisionalNavigation = false
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

        if !BrowserNavigationError.isInterruption(error) {
            delegate?.browserPage(self, didFailNavigationWith: error, failingURL: webView.url)
        }
        originalURL = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // The page shown stays: its own certificate and content again.
        hasProvisionalNavigation = false
        delegate?.browserPageDidChangeSecurity(self)
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

        if BrowserNavigationError.isInterruption(error) {
            return
        }

        delegate?.browserPage(self, didFailNavigationWith: error, failingURL: failingURL)
        originalURL = nil
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust,
           // A digest only for a host with an exception, not every connection.
           certificateExceptions[challenge.protectionSpace.host] != nil,
           CertificateException.isAccepted(
               digest: CertificateException.digest(of: serverTrust),
               host: challenge.protectionSpace.host,
               exceptions: certificateExceptions
           )
        {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else if authenticate(challenge, completionHandler: completionHandler) {
            return
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// A login the server asks for (HTTP Basic, Digest, NTLM): asked to the
    /// user through the delegate. False for any other challenge.
    private func authenticate(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool {
        let space = challenge.protectionSpace
        // A proxy's login stays WebKit's (the sheet speaks of a site).
        guard !space.isProxy() else { return false }
        switch HTTPAuthentication.decision(
            method: space.authenticationMethod, previousFailureCount: challenge.previousFailureCount
        ) {
        case .defaultHandling:
            return false
        case .giveUp:
            completionHandler(.performDefaultHandling, nil)
            return true
        case .ask:
            guard let delegate else {
                completionHandler(.performDefaultHandling, nil)
                return true
            }
            let request = HTTPAuthenticationRequest(
                host: space.host,
                realm: space.realm,
                isSecure: space.receivesCredentialSecurely,
                previousFailureCount: challenge.previousFailureCount,
                proposedUser: challenge.proposedCredential?.user
            )
            delegate.browserPage(self, authenticate: request) { credential in
                // No name and password: the server's refusal shows, as when
                // the login is cancelled in Safari.
                completionHandler(credential == nil ? .performDefaultHandling : .useCredential, credential)
            }
            return true
        }
    }

    @available(macOS 11.3, *)
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let handling = BrowserDownloadPolicy.handling(
            isForMainFrame: navigationResponse.isForMainFrame,
            isDownload: BrowserDownloadPolicy.isDownload(navigationResponse)
        )
        switch handling {
        case .show:
            if navigationResponse.isForMainFrame {
                isDownloadNavigation = false
                originalURL = nil
            }
            decisionHandler(.allow)
        case .frameDownload:
            decisionHandler(.download)
        case .pageDownload:
            isDownloadNavigation = true
            hasProvisionalNavigation = false
            emitNavigationEvent(
                phase: .finished,
                url: originalURL,
                title: webView.title,
                progress: 0,
                isLoading: false
            )
            decisionHandler(.download)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        guard let downloadURL = navigationAction.request.url else { return }
        delegate?.browserPage(self, didStartDownload: BrowserDownloadTask(download: download, originalURL: downloadURL))
    }

    /// A content rule acted on a load (WKNavigationDelegatePrivate, the method
    /// Safari's privacy report uses). Counted for the shield of the address
    /// bar, except cookie-only rules.
    @objc(_webView:contentRuleListWithIdentifier:performedAction:forURL:)
    func webView(
        _ webView: WKWebView,
        contentRuleListWithIdentifier identifier: String,
        performedAction action: NSObject,
        forURL url: URL
    ) {
        guard BrowserPrivacyService.blocksContent(ruleListIdentifier: identifier) else { return }
        notifyOnMain { $0.delegate?.browserPage($0, didBlockContentFrom: url) }
    }

    /// "Download Image", "Download Linked File" and "Download Video" from the
    /// page's context menu. Private WebKit delegate method
    /// (WKNavigationDelegatePrivate, macOS 12+): without it, WebKit creates the
    /// download but nothing takes care of it, so it never starts.
    @objc(_webView:contextMenuDidCreateDownload:)
    func webView(_ webView: WKWebView, contextMenuDidCreate download: WKDownload) {
        guard let downloadURL = download.originalRequest?.url else { return }
        let task = BrowserDownloadTask(download: download, originalURL: downloadURL)
        task.isRequestedByUser = true
        delegate?.browserPage(self, didStartDownload: task)
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        guard let downloadURL = navigationResponse.response.url else { return }
        let task = BrowserDownloadTask(download: download, originalURL: downloadURL)
        delegate?.browserPage(self, didStartDownload: task)
        // A frame's file leaves the page's own load alone (see above).
        if navigationResponse.isForMainFrame {
            isDownloadNavigation = false
            originalURL = nil
        }
    }

    // MARK: - Helpers

    /// The HTTPS address to load instead, for a page loaded in this tab (not
    /// back/forward or reload, which must keep their history entry).
    private func linkTrackingCleanedURL(for navigationAction: WKNavigationAction) -> URL? {
        guard navigationAction.targetFrame?.isMainFrame == true,
              navigationAction.navigationType != .backForward,
              navigationAction.navigationType != .reload,
              navigationAction.request.httpMethod?.uppercased() ?? "GET" == "GET", // not shown
              let url = navigationAction.request.url,
              delegate?.browserPage(self, removesLinkTrackingFrom: url) == true
        else { return nil }
        return LinkTrackingProtection.cleaned(url)
    }

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

    /// Navigation failure caused by the end of the web content process, which is
    /// reported separately by `webViewWebContentProcessDidTerminate(_:)`.
    private func isWebContentProcessTerminationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == WKError.errorDomain
            && nsError.code == WKError.Code.webContentProcessTerminated.rawValue
    }
}
