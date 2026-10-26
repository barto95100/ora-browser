import AppKit
import Foundation
@preconcurrency import WebKit

/// A web page backed by WebKit. The page API lives here; the WebKit delegate
/// conformances are in `BrowserPage+NavigationDelegate.swift`,
/// `BrowserPage+UIDelegate.swift` and `BrowserPage+MediaCapture.swift`.
final class BrowserPage: NSObject, WKScriptMessageHandler {
    weak var delegate: BrowserPageDelegate?

    /// Engine-internal: used by the delegate extensions. Outside the browser
    /// engine, go through the page API (`contentView`, `load`, …).
    let webView: WKWebView
    private let messageNames: [String]
    // Navigation tracking, updated by the navigation delegate extension only.
    var originalURL: URL?
    var lastCommittedURL: URL?
    var isDownloadNavigation = false
    private(set) var sslBypassedHosts: Set<String> = []
    private var isReadyForNavigation = false
    private var pendingLoadRequest: URLRequest?
    private var pendingReload = false
    private var captureStateObservations: [NSKeyValueObservation] = []

    init(
        profile: BrowserEngineProfile,
        configuration: BrowserPageConfiguration,
        delegate: BrowserPageDelegate?
    ) {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.applicationNameForUserAgent = configuration.applicationNameForUserAgent
        webConfiguration.websiteDataStore = profile.dataStore
        webConfiguration.allowsAirPlayForMediaPlayback = configuration.allowsAirPlayForMediaPlayback
        webConfiguration.preferences.setValue(
            configuration.allowsInspectableDebugging,
            forKey: "developerExtrasEnabled"
        )
        webConfiguration.preferences.setValue(
            configuration.allowsPictureInPicture,
            forKey: "allowsPictureInPictureMediaPlayback"
        )
        webConfiguration.preferences.setValue(configuration.allowsJavaScript, forKey: "javaScriptEnabled")
        webConfiguration.preferences.setValue(
            configuration.allowsJavaScriptWindowsAutomatically,
            forKey: "javaScriptCanOpenWindowsAutomatically"
        )
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically =
            configuration.allowsJavaScriptWindowsAutomatically
        webConfiguration.preferences.isElementFullscreenEnabled = true
        webConfiguration.mediaTypesRequiringUserActionForPlayback =
            configuration.mediaPlaybackRequiresUserAction ? .all : []

        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = configuration.allowsJavaScript
        webConfiguration.defaultWebpagePreferences = webpagePreferences

        let contentController = WKUserContentController()
        webConfiguration.userContentController = contentController
        messageNames = configuration.scriptMessageNames
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        self.delegate = delegate

        super.init()

        // Camera/microphone use, to show it and let the user pause it.
        captureStateObservations = [
            webView.observe(\.cameraCaptureState) { [weak self] _, _ in
                self?.mediaCaptureStateDidChange()
            },
            webView.observe(\.microphoneCaptureState) { [weak self] _, _ in
                self?.mediaCaptureStateDidChange()
            }
        ]

        for messageName in configuration.scriptMessageNames {
            contentController.add(self, name: messageName)
        }
        for script in configuration.userScripts {
            let userScript = WKUserScript(
                source: script.source,
                injectionTime: mapInjectionTime(script.injectionTime),
                forMainFrameOnly: script.forMainFrameOnly
            )
            contentController.addUserScript(userScript)
        }

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = configuration.allowsBackForwardNavigationGestures
        webView.wantsLayer = true
        webView.isInspectable = configuration.allowsInspectableDebugging
        if let layer = webView.layer {
            layer.isOpaque = true
            layer.drawsAsynchronously = true
        }

        BrowserPrivacyService.shared.prepareConfiguration(
            webConfiguration,
            spaceID: profile.identifier
        ) { [weak self] in
            self?.isReadyForNavigation = true
            self?.flushPendingNavigationIfNeeded()
        }
    }

    var contentView: NSView {
        webView
    }

    var window: NSWindow? {
        webView.window
    }

    var currentURL: URL? {
        webView.url
    }

    var title: String? {
        webView.title
    }

    var canGoBack: Bool {
        webView.canGoBack
    }

    var canGoForward: Bool {
        webView.canGoForward
    }

    var isLoading: Bool {
        webView.isLoading
    }

    var estimatedProgress: Double {
        webView.estimatedProgress
    }

    func load(_ request: URLRequest) {
        guard isReadyForNavigation else {
            pendingLoadRequest = request
            pendingReload = false
            return
        }

        perform(request)
    }

    /// The app is sandboxed: WebKit may only read a local file loaded through
    /// `loadFileURL(_:allowingReadAccessTo:)`, scoped to that file (the one the
    /// user opened), not with a plain request.
    private func perform(_ request: URLRequest) {
        if let url = request.url, url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            webView.load(request)
        }
    }

    func reload() {
        guard isReadyForNavigation else {
            pendingReload = true
            pendingLoadRequest = nil
            return
        }

        webView.reload()
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func stopLoading() {
        webView.stopLoading()
    }

    func evaluateJavaScript(_ script: String, completion: ((Any?, Error?) -> Void)? = nil) {
        webView.evaluateJavaScript(script, completionHandler: completion)
    }

    func takeSnapshot(
        configuration: BrowserSnapshotConfiguration,
        completion: @escaping (NSImage?, Error?) -> Void
    ) {
        let snapshotConfiguration = WKSnapshotConfiguration()
        snapshotConfiguration.afterScreenUpdates = configuration.afterScreenUpdates
        if let rect = configuration.rect {
            snapshotConfiguration.rect = rect
        }
        webView.takeSnapshot(with: snapshotConfiguration, completionHandler: completion)
    }

    func closeMediaPresentations(completion: @escaping () -> Void) {
        webView.closeAllMediaPresentations(completionHandler: completion)
    }

    func teardown() {
        captureStateObservations.forEach { $0.invalidate() }
        captureStateObservations = []
        // Release the camera and microphone right away, not when WebKit frees
        // the page later (the camera light would stay on after closing a tab).
        if webView.cameraCaptureState != .none {
            webView.setCameraCaptureState(.none, completionHandler: nil)
        }
        if webView.microphoneCaptureState != .none {
            webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        for messageName in messageNames {
            controller.removeScriptMessageHandler(forName: messageName)
        }
        webView.removeFromSuperview()
    }

    func bypassSSL(for host: String) {
        sslBypassedHosts.insert(host)
    }

    private func flushPendingNavigationIfNeeded() {
        if let pendingLoadRequest {
            self.pendingLoadRequest = nil
            perform(pendingLoadRequest)
            return
        }

        if pendingReload {
            pendingReload = false
            webView.reload()
        }
    }

    private func mapInjectionTime(_ injectionTime: BrowserUserScriptInjectionTime) -> WKUserScriptInjectionTime {
        switch injectionTime {
        case .atDocumentStart:
            .atDocumentStart
        case .atDocumentEnd:
            .atDocumentEnd
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.browserPage(
            self,
            didReceiveScriptMessage: BrowserScriptMessage(name: message.name, body: message.body)
        )
    }
}
