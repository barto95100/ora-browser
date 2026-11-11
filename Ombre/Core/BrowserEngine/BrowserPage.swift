import AppKit
import Foundation
@preconcurrency import WebKit

/// A web page backed by WebKit. The page API lives here; the WebKit delegate
/// conformances are in `BrowserPage+NavigationDelegate.swift`,
/// `BrowserPage+UIDelegate.swift` and `BrowserPage+MediaCapture.swift`.
final class BrowserPage: NSObject, WKScriptMessageHandler {
    weak var delegate: BrowserPageDelegate?
    /// Made with an extension's configuration, for its own pages: WebKit
    /// loads nothing else in it (a website it leads to opens in a tab).
    var isExtensionPage = false

    /// Engine-internal: used by the delegate extensions. Outside the browser
    /// engine, go through the page API (`contentView`, `load`, …).
    let webView: WKWebView
    private let messageNames: [String]
    // Navigation tracking, updated by the navigation delegate extension only.
    var originalURL: URL?
    var lastCommittedURL: URL?
    var isDownloadNavigation = false
    /// Certificates the user chose to trust anyway, by host (SHA-256, see
    /// `CertificateException`).
    private(set) var certificateExceptions: [String: String] = [:]
    private(set) var isReadyForNavigation = false
    private var pendingLoadRequest: URLRequest?
    private var pendingReload = false
    private var observations: [NSKeyValueObservation] = []
    private nonisolated(unsafe) var inspectionObserver: NSObjectProtocol?
    /// HTTPS first, see `HTTPSUpgradePolicy`. Used by the navigation delegate.
    var httpsUpgrade = HTTPSUpgradePolicy()
    /// How the next new tab asked by the page opens (context menu items, see
    /// `BrowserPage+ContextMenu.swift`).
    var pendingNewTabDisposition: (disposition: BrowserNewTabDisposition, date: Date)?
    /// The space's content rule lists (ads, trackers, cookies), taken off for
    /// a site exempted from protections.
    private var contentRuleLists: [WKContentRuleList] = []
    private(set) var isContentBlockingEnabled = true

    /// The content rules applied to the page now (none on an exempted site).
    var activeContentRuleLists: [WKContentRuleList] {
        isContentBlockingEnabled ? contentRuleLists : []
    }

    /// The space's content rules, applied or not on the current site (an
    /// exemption is for one site, not the next page).
    var spaceContentRuleLists: [WKContentRuleList] {
        contentRuleLists
    }
    /// Owned here: the content controller only gets a weak proxy to it.
    var notificationBridge: WebNotificationBridge?
    /// The secret event name the app tells the page's notifications with
    /// (see `WebNotificationScript`): a page can't guess it.
    let notificationChannel = "n" + UUID().uuidString.replacingOccurrences(of: "-", with: "")

    /// `webKitConfiguration`: the one WebKit gives for a window a page opens
    /// (`window.open`), which the new page must use to stay linked to it
    /// (same process and data, `window.opener`); it is the opener's, so the
    /// page only gets its own scripts and handlers.
    init(
        profile: BrowserEngineProfile,
        configuration: BrowserPageConfiguration,
        delegate: BrowserPageDelegate?,
        webKitConfiguration: WKWebViewConfiguration? = nil,
        inheritedRuleLists: [WKContentRuleList] = []
    ) {
        let webConfiguration = webKitConfiguration ?? WKWebViewConfiguration()
        if webKitConfiguration == nil {
            Self.configure(webConfiguration, profile: profile, configuration: configuration)
        }

        let contentController = WKUserContentController()
        // A window a page opens loads at once: its opener's protections apply
        // from the first request, not once its own are ready.
        inheritedRuleLists.forEach(contentController.add)
        webConfiguration.userContentController = contentController
        contentRuleLists = inheritedRuleLists
        messageNames = configuration.scriptMessageNames
        let ombreWebView = OmbreWebView(frame: .zero, configuration: webConfiguration)
        webView = ombreWebView
        self.delegate = delegate

        super.init()
        setUp(
            ombreWebView,
            contentController: contentController,
            configuration: configuration,
            webConfiguration: webConfiguration,
            profile: profile
        )
    }

    /// A new page's own settings (not for a window a page opens: those come
    /// with WebKit's configuration, from its opener).
    private static func configure(
        _ webConfiguration: WKWebViewConfiguration,
        profile: BrowserEngineProfile,
        configuration: BrowserPageConfiguration
    ) {
        webConfiguration.applicationNameForUserAgent = configuration.applicationNameForUserAgent
        webConfiguration.websiteDataStore = profile.dataStore
        webConfiguration.allowsAirPlayForMediaPlayback = configuration.allowsAirPlayForMediaPlayback
        // Public preferences only (JavaScript is set per page below), except
        // Picture in Picture (`PictureInPicturePreference`, the one private
        // setting shipped) and the Debug-only inspector key (`applyInspection`).
        PictureInPicturePreference.enable(in: webConfiguration.preferences)
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically =
            configuration.allowsJavaScriptWindowsAutomatically
        webConfiguration.preferences.isElementFullscreenEnabled = true
        webConfiguration.mediaTypesRequiringUserActionForPlayback =
            configuration.mediaPlaybackRequiresUserAction ? .all : []

        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = configuration.allowsJavaScript
        webConfiguration.defaultWebpagePreferences = webpagePreferences

        // Extensions: in private windows (a non-persistent store), WebKit runs
        // only those allowed in private browsing (`hasAccessToPrivateData`).
        if #available(macOS 15.4, *),
           let controller = BrowserEngine.shared.webExtensionController as? WKWebExtensionController
        {
            webConfiguration.webExtensionController = controller
        }
    }

    private func setUp(
        _ ombreWebView: OmbreWebView,
        contentController: WKUserContentController,
        configuration: BrowserPageConfiguration,
        webConfiguration: WKWebViewConfiguration,
        profile: BrowserEngineProfile
    ) {
        ombreWebView.contextMenuOwner = self
        // Positions for its pages (`GeolocationProvider`, WebKit has none on macOS).
        if let pool = processPool(of: ombreWebView.configuration) { GeolocationProvider.shared.install(on: pool) }

        observations = [
            // Address and title, including same-page navigations (history API,
            // fragments): WebKit reports them, no polling from the page needed.
            webView.observe(\.url) { [weak self] _, _ in
                self?.notifyOnMain { $0.delegate?.browserPage($0, didChangeURL: $0.webView.url) }
            },
            webView.observe(\.title) { [weak self] _, _ in
                self?.notifyOnMain { $0.delegate?.browserPage($0, didChangeTitle: $0.webView.title) }
            },
            // The header color the page asks for, without polling it.
            webView.observe(\.themeColor) { [weak self] _, _ in
                self?.notifyOnMain { $0.delegate?.browserPage($0, didChangeThemeColor: $0.webView.themeColor) }
            },
            // Camera/microphone use, to show it and let the user pause it.
            webView.observe(\.cameraCaptureState) { [weak self] _, _ in
                self?.mediaCaptureStateDidChange()
            },
            webView.observe(\.microphoneCaptureState) { [weak self] _, _ in
                self?.mediaCaptureStateDidChange()
            },
            // Insecure content loaded by a secure page (the lock goes).
            webView.observe(\.hasOnlySecureContent) { [weak self] _, _ in
                self?.notifyOnMain { $0.delegate?.browserPageDidChangeSecurity($0) }
            }
        ]

        // Through a weak proxy: the controller must not keep the page alive.
        // In the app's world: the page can't post to them.
        for messageName in configuration.scriptMessageNames {
            contentController.add(WeakScriptMessageHandler(self), contentWorld: Self.appWorld, name: messageName)
        }
        for script in configuration.userScripts {
            let userScript = WKUserScript(
                source: script.source,
                injectionTime: mapInjectionTime(script.injectionTime),
                forMainFrameOnly: script.forMainFrameOnly,
                in: Self.contentWorld(script.world)
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
        applyInspection()
        inspectionObserver = NotificationCenter.default.addObserver(
            forName: BrowserEngine.inspectionDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyInspection() }
        }
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

    /// Clears this page's own store (a private window's session included),
    /// all of it or one website's.
    func clearWebsiteData(
        ofTypes types: Set<BrowserWebsiteDataType>,
        forHost host: String?,
        completion: (@MainActor () -> Void)? = nil
    ) {
        BrowserEngineProfile.clearData(
            in: webView.configuration.websiteDataStore, ofTypes: types, forHost: host, completion: completion
        )
    }

    var contentView: NSView {
        webView
    }

    /// The page's zoom (1: actual size), kept across its navigations.
    var pageZoom: Double {
        get { Double(webView.pageZoom) }
        set { webView.pageZoom = CGFloat(newValue) }
    }

    /// Hides the mouse from the page under a floating panel (nil: no panel).
    func setMouseShield(_ shield: MouseShield?) {
        (webView as? OmbreWebView)?.mouseShield = shield
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

    /// Whether everything the page loaded came over a secure connection.
    var hasOnlySecureContent: Bool {
        webView.hasOnlySecureContent
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

    /// Runs `script` in the app's world (see `BrowserScriptWorld`): it sees
    /// the page's document and the app's scripts, not the page's variables.
    func evaluateJavaScript(_ script: String, completion: ((Any?, Error?) -> Void)? = nil) {
        webView.evaluateJavaScript(script, in: nil, in: Self.appWorld) { result in
            guard let completion else { return }
            switch result {
            case let .success(value): completion(value, nil)
            case let .failure(error): completion(nil, error)
            }
        }
    }

    /// The world of the app's scripts, apart from the page's.
    static let appWorld = WKContentWorld.world(name: "app")

    static func contentWorld(_ world: BrowserScriptWorld) -> WKContentWorld {
        switch world {
        case .app: appWorld
        case .page: .page
        }
    }

    /// The color the page asks the browser's chrome to use, if any.
    var themeColor: NSColor? {
        webView.themeColor
    }

    func takeSnapshot(
        configuration: BrowserSnapshotConfiguration,
        completion: @escaping @MainActor @Sendable (NSImage?, Error?) -> Void
    ) {
        let snapshotConfiguration = WKSnapshotConfiguration()
        snapshotConfiguration.afterScreenUpdates = configuration.afterScreenUpdates
        if let rect = configuration.rect {
            snapshotConfiguration.rect = rect
        }
        if let width = configuration.width {
            snapshotConfiguration.snapshotWidth = NSNumber(value: Double(width))
        }
        webView.takeSnapshot(with: snapshotConfiguration, completionHandler: completion)
    }

    func closeMediaPresentations(completion: @escaping @MainActor @Sendable () -> Void) {
        webView.closeAllMediaPresentations(completionHandler: completion)
    }

    /// Safari's Web Inspector, through the public `isInspectable` (its Develop
    /// menu). Debug builds also get "Inspect Element" in the context menu,
    /// a private preference.
    private func applyInspection() {
        let allowsInspection = BrowserEngine.shared.allowsInspection
        webView.isInspectable = allowsInspection
        #if DEBUG
            webView.configuration.preferences.setValue(allowsInspection, forKey: "developerExtrasEnabled")
        #endif
    }

    deinit {
        if let inspectionObserver {
            NotificationCenter.default.removeObserver(inspectionObserver)
        }
    }

    func teardown() {
        observations.forEach { $0.invalidate() }
        observations = []
        if let inspectionObserver {
            NotificationCenter.default.removeObserver(inspectionObserver)
            self.inspectionObserver = nil
        }
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
        // The handlers are weak proxies (no cycle to break): removed so no
        // message reaches the page once it is torn down.
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        for messageName in messageNames {
            controller.removeScriptMessageHandler(forName: messageName, contentWorld: Self.appWorld)
        }
        controller.removeScriptMessageHandler(forName: WebNotificationBridge.messageName, contentWorld: Self.appWorld)
        webView.removeFromSuperview()
    }

    /// Trusts this certificate for `host`, and no other one it may present.
    func allowCertificate(digest: String, for host: String) {
        certificateExceptions[host] = digest
    }

    private func flushPendingNavigationIfNeeded() {
        if let pendingLoadRequest {
            self.pendingLoadRequest = nil
            perform(pendingLoadRequest)
            return
        }

        if pendingReload {
            pendingReload = false
            // Through `reload()`: a local file keeps its read access.
            reload()
        }
    }

    /// KVO may notify on any thread; the delegate updates the interface.
    nonisolated func notifyOnMain(_ body: @escaping @MainActor @Sendable (BrowserPage) -> Void) {
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
