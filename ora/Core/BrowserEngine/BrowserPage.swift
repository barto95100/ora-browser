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
    private var observations: [NSKeyValueObservation] = []
    /// HTTPS first, see `HTTPSUpgradePolicy`. Used by the navigation delegate.
    var httpsUpgrade = HTTPSUpgradePolicy()
    /// How the next new tab asked by the page opens (context menu items, see
    /// `BrowserPage+ContextMenu.swift`).
    var pendingNewTabDisposition: (disposition: BrowserNewTabDisposition, date: Date)?
    /// The space's content rule lists (ads, trackers, cookies), taken off for
    /// a site exempted from protections.
    private var contentRuleLists: [WKContentRuleList] = []
    private(set) var isContentBlockingEnabled = true

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
        // Extensions: in private windows (a non-persistent store), WebKit runs
        // only those allowed in private browsing (`hasAccessToPrivateData`).
        if #available(macOS 15.4, *),
           let controller = BrowserEngine.shared.webExtensionController as? WKWebExtensionController
        {
            webConfiguration.webExtensionController = controller
        }
        messageNames = configuration.scriptMessageNames
        let oraWebView = OraWebView(frame: .zero, configuration: webConfiguration)
        webView = oraWebView
        self.delegate = delegate

        super.init()
        oraWebView.contextMenuOwner = self

        observations = [
            // Address and title, including same-page navigations (history API,
            // fragments): WebKit reports them, no polling from the page needed.
            webView.observe(\.url) { [weak self] _, _ in
                self?.notifyOnMain { $0.delegate?.browserPage($0, didChangeURL: $0.webView.url) }
            },
            webView.observe(\.title) { [weak self] _, _ in
                self?.notifyOnMain { $0.delegate?.browserPage($0, didChangeTitle: $0.webView.title) }
            },
            // Camera/microphone use, to show it and let the user pause it.
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
        if configuration.enablesWebNotifications {
            installWebNotifications(in: contentController)
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
        ) { [weak self] ruleLists in
            guard let self else { return }
            contentRuleLists = ruleLists
            if !isContentBlockingEnabled {
                webView.configuration.userContentController.removeAllContentRuleLists()
            }
            isReadyForNavigation = true
            flushPendingNavigationIfNeeded()
        }
    }

    var contentView: NSView {
        webView
    }

    /// The web view, for the extensions' tabs API only (`ExtensionTab`).
    var extensionWebView: WKWebView {
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
    /// user opened), or to its folder when the user allowed it (so the page's
    /// images and styles load), not with a plain request.
    private func perform(_ request: URLRequest) {
        if let url = request.url, url.isFileURL {
            let readAccess = LocalFolderAccess.shared.folder(containing: url) ?? url
            webView.loadFileURL(url, allowingReadAccessTo: readAccess)
        } else {
            webView.load(request)
        }
    }

    /// Content blocking on or off for the page (a site exempted from
    /// protections). Applies to the next loads.
    func setContentBlocking(enabled: Bool) {
        guard enabled != isContentBlockingEnabled else { return }
        isContentBlockingEnabled = enabled
        let controller = webView.configuration.userContentController
        if enabled {
            contentRuleLists.forEach(controller.add)
        } else {
            controller.removeAllContentRuleLists()
        }
    }

    func reload() {
        guard isReadyForNavigation else {
            pendingReload = true
            pendingLoadRequest = nil
            return
        }

        // A local file is loaded again with its read access (a plain reload
        // is refused by the sandbox once its first load failed).
        if let url = webView.url, url.isFileURL {
            perform(URLRequest(url: url))
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
        observations.forEach { $0.invalidate() }
        observations = []
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
        controller.removeScriptMessageHandler(forName: WebNotificationBridge.messageName, contentWorld: .page)
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

    /// KVO may notify on any thread; the delegate updates the interface.
    func notifyOnMain(_ body: @escaping (BrowserPage) -> Void) {
        DispatchQueue.main.async { [weak self] in
            if let self { body(self) }
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
        // Popups share this page's configuration, hence its message handlers:
        // their messages are not about this page.
        guard message.webView === webView else { return }
        // Only our main-frame scripts may talk to us: drop messages from
        // iframes and late ones from a page we already navigated away from.
        let frameOrigin = message.frameInfo.securityOrigin
        guard ScriptMessagePolicy.accepts(
            isMainFrame: message.frameInfo.isMainFrame,
            frameScheme: frameOrigin.protocol,
            frameHost: frameOrigin.host,
            framePort: frameOrigin.port,
            pageURL: webView.url
        ) else { return }
        delegate?.browserPage(
            self,
            didReceiveScriptMessage: BrowserScriptMessage(name: message.name, body: message.body)
        )
    }
}
