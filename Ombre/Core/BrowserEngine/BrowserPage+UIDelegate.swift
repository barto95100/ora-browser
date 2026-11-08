import CoreLocation
import AppKit
import Foundation
@preconcurrency import WebKit

extension BrowserPage: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let permission: BrowserPermissionKind = switch type {
        case .camera: .camera
        case .microphone: .microphone
        case .cameraAndMicrophone: .cameraAndMicrophone
        @unknown default: .cameraAndMicrophone
        }
        delegate?.browserPage(self, requestPermission: permission, origin: url(of: origin)) { decision in
            decisionHandler(Self.webKitDecision(decision))
        }
    }

    /// A page asks for the device's location: the site's permission in its
    /// space, asked in the page like the camera. macOS 27's public method;
    /// before it, WebKit's private delegate method below (the one Safari
    /// implements), the only way there.
    @available(macOS 27.0, *)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        requestGeolocation(for: origin, decisionHandler: decisionHandler)
    }

    /// Before macOS 27 (WKUIDelegatePrivate, macOS 12+): see above.
    /// `GeolocationPermissionTests` fails if WebKit no longer declares it.
    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    func requestGeolocationBeforeMacOS27(
        _ webView: WKWebView,
        origin: WKSecurityOrigin,
        frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        requestGeolocation(for: origin, decisionHandler: decisionHandler)
    }

    /// A page asks to share a screen or a window (`getDisplayMedia`):
    /// WebKit's private delegate method, the only way on macOS (see
    /// `ScreenSharing`). The site's permission, then macOS's picker.
    @objc(_webView:requestDisplayCapturePermissionForOrigin:initiatedByFrame:withSystemAudio:decisionHandler:)
    func requestDisplayCapture(
        _ webView: WKWebView,
        origin: WKSecurityOrigin,
        frame: WKFrameInfo,
        withSystemAudio: Bool,
        decisionHandler: @escaping (Int) -> Void
    ) {
        guard let delegate else {
            decisionHandler(ScreenSharing.Decision.deny.rawValue)
            return
        }
        delegate.browserPage(self, requestPermission: .screen, origin: url(of: origin)) { decision in
            let answer: ScreenSharing.Decision = decision == .grant ? .screenPrompt : .deny
            decisionHandler(answer.rawValue)
        }
    }

    static var isLocationDeniedBySystem: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .denied || status == .restricted
    }

    private func requestGeolocation(
        for origin: WKSecurityOrigin,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        guard let delegate else {
            decisionHandler(.deny)
            return
        }
        delegate.browserPage(self, requestPermission: .geolocation, origin: url(of: origin)) { decision in
            decisionHandler(Self.webKitDecision(decision))
        }
    }

    /// Answers `navigator.permissions.query()`. Private WebKit delegate method
    /// (WKUIDelegatePrivate, macOS 13+), the one Safari implements: without it,
    /// WebKit's answer ignores the user's per-site decisions. WebKit then adjusts
    /// the answer like in Safari (e.g. a denial reads as "prompt" until the page
    /// itself was denied).
    @objc(_webView:queryPermission:forOrigin:completionHandler:)
    func webView(
        _ webView: WKWebView,
        queryPermission name: String,
        forOrigin origin: WKSecurityOrigin,
        completionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let permission: BrowserPermissionKind? = switch name {
        case "camera": .camera
        case "microphone": .microphone
        case "notifications": .notifications
        case "geolocation": .geolocation
        default: nil
        }
        guard let permission, let delegate else {
            // Other permissions: WebKit's own default answer.
            completionHandler(.prompt)
            return
        }
        // Location refused to Ombre in macOS's settings: the site can't have
        // it either, whatever it was allowed.
        if permission == .geolocation, Self.isLocationDeniedBySystem {
            completionHandler(.deny)
            return
        }
        let decision = delegate.browserPage(self, queryPermission: permission, origin: url(of: origin))
        completionHandler(Self.webKitDecision(decision))
    }

    private func url(of origin: WKSecurityOrigin) -> URL? {
        URL(string: "\(origin.protocol)://\(origin.host):\(origin.port)")
    }

    private static func webKitDecision(_ decision: BrowserPermissionDecision) -> WKPermissionDecision {
        switch decision {
        case .grant: .grant
        case .deny: .deny
        case .prompt: .prompt
        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        delegate?.browserPage(
            self,
            runOpenPanelWith: BrowserOpenPanelOptions(
                allowsDirectories: parameters.allowsDirectories,
                allowsMultipleSelection: parameters.allowsMultipleSelection
            ),
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // A sized `window.open` is a popup (e.g. "Sign in with…"): it gets its
        // own window, linked to this page. Anything else opens in a new tab.
        if BrowserPopupWindow.isPopup(windowFeatures) {
            return MainActor.assumeIsolated {
                BrowserPopupWindow.open(
                    configuration: configuration,
                    windowFeatures: windowFeatures,
                    openerWindow: webView.window,
                    opener: self,
                    openerOrigin: PopupTitle.origin(of: navigationAction.sourceFrame)
                )
            }
        }
        // A click on a `target="_blank"` link (not a script, not "Open Link in
        // New Tab" from the context menu): Peek, from a pinned tab, like a
        // plain link (see `PeekPolicy`).
        if navigationAction.navigationType == .linkActivated, !hasPendingNewTabDisposition,
           let url = navigationAction.request.url,
           delegate?.browserPage(self, opensNewWindowLink: url, modifierFlags: navigationAction.modifierFlags) == true
        {
            return nil
        }
        // Else a tab linked to this page (`window.opener`, `postMessage`), like
        // Safari: sign-in and payment pages opened this way wait for an answer.
        let disposition = takeNewTabDisposition()
        if let linked = delegate?.browserPage(
            self, linkedPageWith: configuration, for: navigationAction.request.url, disposition: disposition
        ) {
            return linked
        }
        if let url = navigationAction.request.url {
            delegate?.browserPage(self, didRequestOpenInNewTab: url, disposition: disposition)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        // Answered once the dialog is closed, not before: the page waits.
        runDialog(.alert, message: message, frame: frame) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        runDialog(.confirm, message: message, frame: frame) { completionHandler($0.isConfirmed) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        runDialog(.prompt(defaultText: defaultText ?? ""), message: prompt, frame: frame) { reply in
            completionHandler(reply.isConfirmed ? reply.text : nil)
        }
    }

    private func runDialog(
        _ kind: BrowserJavaScriptDialog.Kind,
        message: String,
        frame: WKFrameInfo,
        completion: @escaping (BrowserJavaScriptDialogReply) -> Void
    ) {
        let origin = frame.securityOrigin
        let host = origin.host.isEmpty ? origin.protocol : origin.host
        let dialog = BrowserJavaScriptDialog(kind: kind, message: message, host: host)
        guard let delegate else {
            completion(.refused)
            return
        }
        delegate.browserPage(self, runJavaScriptDialog: dialog, completion: completion)
    }
}
