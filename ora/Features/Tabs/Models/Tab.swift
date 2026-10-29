import AppKit
import SwiftData
import SwiftUI

enum TabType: String, Codable {
    case pinned
    case fav
    case normal
}

// MARK: - Tab

@Model
class Tab: ObservableObject, Identifiable {
    var id: UUID
    var url: URL
    var urlString: String
    var savedURL: URL?
    var title: String
    var favicon: URL? // Add favicon property
    var createdAt: Date
    var lastAccessedAt: Date?

    var type: TabType
    var order: Int
    var faviconLocalFile: URL?
    var backgroundColorHex: String = "#000000"
    /// Security-scoped bookmark to the local file this tab shows, so it can be
    /// read again after a relaunch (see `Tab+LocalFile.swift`).
    var fileBookmark: Data?
    /// Split View: the tab shown at the right of this one (see `TabSplits`).
    var splitRightTabID: UUID?
    /// Split View: share of the width this tab takes when it is the left side.
    var splitFraction: Double = 0.5
    /// Folder of the pinned section this tab is in (see `TabFolders`).
    var folderID: UUID?

    //    @Transient @Published var backgroundColor: Color = Color(.black)
    /// Published so the sidebar's speaker icon follows playback.
    @Transient @Published var isPlayingMedia: Bool = false
    @Transient var isLoading: Bool = false
    /// Set while the tab is being closed, so it is not picked as the next tab.
    @Transient var isClosing = false
    @Transient @Published var backgroundColor: Color = .black
    @Transient var historyManager: HistoryManager?
    @Transient var downloadManager: DownloadManager?
    @Transient var tabManager: TabManager?
    @Transient var browserPage: BrowserPage?
    @Transient var pageDelegate: TabBrowserPageDelegate?
    @Transient @Published var isWebViewReady: Bool = false
    @Transient @Published var loadingProgress: Double = 10.0
    @Transient var colorUpdated = false
    @Transient var maybeIsActive = false
    @Transient @Published var hasNavigationError: Bool = false
    @Transient @Published var navigationError: Error?
    @Transient @Published var failedURL: URL?
    @Transient @Published var hoveredLinkURL: String?
    @Transient var isPrivate: Bool = false
    @Transient var passwordCoordinator: PasswordAutofillCoordinator?
    @Transient @Published var passwordOverlayState: PasswordAutofillOverlayState?
    @Transient @Published var passwordTriggerOverlayState: PasswordAutofillOverlayState?
    /// Permission prompt currently shown for this tab, see `Tab+SitePermissions`.
    @Transient @Published var permissionRequest: SitePermissionRequest?
    @Transient var crashRecovery = PageCrashRecoveryPolicy()
    @Transient var isReloadingAfterCrash = false
    @Transient @Published var showsCrashRecoveryNotice = false
    @Transient @Published var mediaCaptureState = BrowserMediaCaptureState()
    /// Site the shown favicon belongs to (see `Tab+Favicon.swift`).
    @Transient var faviconSiteHost: String?
    /// Last page recorded in the history (see `Tab+History.swift`).
    @Transient var lastRecordedVisitURL: URL?
    /// Local file this tab currently has sandbox access to (see `Tab+LocalFile.swift`).
    @Transient var fileAccessURL: URL?
    /// Folder of a local page whose images and styles are blocked, offered to
    /// the user (see `Tab+LocalFile.swift`).
    @Transient @Published var folderAccessRequest: URL?
    /// Loads kept from the current page by content rules, by host (see
    /// `Tab+Protections.swift`).
    @Transient @Published var blockedContent: [String: Int] = [:]

    @Relationship(inverse: \TabContainer.tabs) var container: TabContainer

    /// Whether this tab is considered alive (recently accessed)
    var isAlive: Bool {
        guard let lastAccessed = lastAccessedAt else { return false }
        let timeout = SettingsStore.shared.tabAliveTimeout
        return Date().timeIntervalSince(lastAccessed) < timeout
    }

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        favicon: URL? = nil,
        container: TabContainer,
        type: TabType = .normal,
        isPlayingMedia: Bool = false,
        order: Int,
        historyManager: HistoryManager? = nil,
        downloadManager: DownloadManager? = nil,
        tabManager: TabManager,
        isPrivate: Bool
    ) {
        let nowDate = Date()
        self.id = id
        self.url = url
        self.urlString = url.absoluteString

        self.title = title
        self.favicon = favicon
        self.createdAt = nowDate
        self.lastAccessedAt = nowDate
        self.type = type
        self.isPlayingMedia = isPlayingMedia
        self.container = container
        self.order = order
        self.historyManager = historyManager
        self.downloadManager = downloadManager
        self.tabManager = tabManager
        self.isPrivate = isPrivate
        self.passwordCoordinator = PasswordAutofillCoordinator(tab: self)
        self.isWebViewReady = false
    }

    func syncBackgroundColorFromHex() {
        backgroundColor = Color(hex: backgroundColorHex)
    }

    /// Call this whenever the color is set
    func updateBackgroundColor(_ color: Color) {
        backgroundColor = color
        backgroundColorHex = color.toHex() ?? "#000000"
    }

    func switchSections(from: Tab, to: Tab) {
        if to.type != .pinned {
            from.folderID = nil
        }
        from.type = to.type
        switch to.type {
        case .pinned, .fav:
            from.savedURL = from.url
        case .normal:
            from.savedURL = nil
        }
    }

    func updateHeaderColor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if let page = self?.browserPage {
                self?.pageDelegate?.takeSnapshotAfterLoad(page)
            }
        }
    }

    func updateHistory() {
        if let historyManager = self.historyManager {
            Task { @MainActor in
                historyManager.record(
                    title: self.title,
                    url: self.url,
                    faviconURL: self.favicon,
                    faviconLocalFile: self.faviconLocalFile,
                    container: self.container
                )
            }
        }
    }

    func maintainSnapShots() {
        if !self.colorUpdated || self.browserPage?.isLoading == true, self.maybeIsActive {
            self.updateHeaderColor()

            Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                guard let tab = self else { return }
                tab.maintainSnapShots()
            }
        }
    }

    func setupBrowserPageDelegate(for page: BrowserPage) {
        let delegate = TabBrowserPageDelegate()
        delegate.tab = self
        delegate.mediaController = tabManager?.mediaController
        delegate.passwordCoordinator = passwordCoordinator
        page.delegate = delegate
        pageDelegate = delegate
    }

    func goForward() {
        lastAccessedAt = Date()
        browserPage?.goForward()
        updateHeaderColor()
    }

    func goBack() {
        lastAccessedAt = Date()
        browserPage?.goBack()
        updateHeaderColor()
    }

    /// A page in this tab's space and privacy mode, with Ora's scripts and the
    /// space's privacy settings.
    func makeBrowserPage(isPrivate: Bool) -> BrowserPage {
        let engine = BrowserEngine.shared
        let profile = engine.makeProfile(identifier: container.id, isPrivate: isPrivate)
        let privacySettings = SettingsStore.shared.privacySettings(for: container.id)
        let userScripts = OraBrowserScripts.userScripts() + BrowserPrivacyService.privacyScripts(
            for: privacySettings,
            spaceID: container.id,
            isPrivate: isPrivate
        )
        return engine.makePage(
            profile: profile,
            configuration: BrowserPageConfiguration.oraDefault(
                userScripts: userScripts,
                privacySettings: privacySettings,
                enablesWebNotifications: !isPrivate
            ),
            delegate: nil
        )
    }

    func restoreTransientState(
        historyManager: HistoryManager,
        downloadManager: DownloadManager,
        tabManager: TabManager,
        isPrivate: Bool
    ) {
        // Avoid double initialization
        if browserPage != nil { return }

        if passwordCoordinator == nil {
            passwordCoordinator = PasswordAutofillCoordinator(tab: self)
        }

        let page = makeBrowserPage(isPrivate: isPrivate)
        browserPage = page

        self.historyManager = historyManager
        self.downloadManager = downloadManager
        self.tabManager = tabManager
        self.isWebViewReady = false
        self.setupBrowserPageDelegate(for: page)
        self.syncBackgroundColorFromHex()
        // Load after a short delay to ensure layout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.beginFileAccessIfNeeded()
            let url = if self.type != .normal { self.savedURL } else { self.url }
            page.load(URLRequest(url: url ?? self.url))
            self.isWebViewReady = true
        }
    }

    func stopMedia(completed: @escaping () -> Void) {
        guard let page = browserPage else {
            completed()
            return
        }

        let js = """
        document.querySelectorAll('video, audio').forEach(el => {
            try {
                el.pause();
                el.src = '';
                el.load();
            } catch (e) {}
        });
        """
        // Silence first: closing Picture in Picture is animated and takes a
        // moment, during which the sound kept playing.
        page.pauseAllMedia { [weak self] in
            page.evaluateJavaScript(js) { _, _ in
                page.closeMediaPresentations {
                    page.teardown()
                    if self?.browserPage === page {
                        self?.browserPage = nil
                        self?.pageDelegate = nil
                        self?.endFileAccess()
                    }
                    completed()
                }
            }
        }
    }

    /// Updates the tab's URL and keeps the persisted `urlString` in sync.
    ///
    /// `urlString` is what open-tab search queries match against, so it must
    /// follow navigation instead of keeping the URL the tab was created with.
    func updateURL(_ newURL: URL) {
        url = newURL
        urlString = newURL.absoluteString
    }

    func loadURL(_ urlString: String) {
        lastAccessedAt = Date()
        let input = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Try to construct a direct URL (has scheme or valid domain+TLD/IP)
        if let directURL = constructURL(from: input) {
            browserPage?.load(URLRequest(url: directURL))
            return
        }

        // 2) Otherwise, treat as a search query using the selected search engine
        let searchEngineService = SearchEngineService()
        if let engine = searchEngineService.getDefaultSearchEngine(for: self.container.id),
           let searchURL = searchEngineService.createSearchURL(for: engine, query: input)
        {
            browserPage?.load(URLRequest(url: searchURL))
            return
        }

        // 3) Fallback to Google if for some reason engine lookup fails
        if let fallbackURL = URL(string: "https://www.google.com/search?client=safari&rls=en&ie=UTF-8&oe=UTF-8&q="
            + (input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        ) {
            browserPage?.load(URLRequest(url: fallbackURL))
        }
    }

    func destroyWebView() {
        cancelPermissionRequest()
        // A new page loads from scratch: nothing left to recover.
        crashRecovery = PageCrashRecoveryPolicy()
        isReloadingAfterCrash = false
        showsCrashRecoveryNotice = false
        if mediaCaptureState.isCapturing { mediaCaptureState = BrowserMediaCaptureState() }
        browserPage?.teardown()
        browserPage = nil
        pageDelegate = nil
        isWebViewReady = false
        endFileAccess()
    }

    func setNavigationError(_ error: Error, for url: URL?) {
        DispatchQueue.main.async {
            self.hasNavigationError = true
            self.navigationError = error
            self.failedURL = url
        }
    }

    func clearNavigationError() {
        DispatchQueue.main.async {
            self.hasNavigationError = false
            self.navigationError = nil
            self.failedURL = nil
        }
    }

    func retryNavigation() {
        // A crashed page reloads in place, keeping its back/forward history.
        if navigationError is PageCrashError {
            crashRecovery.recordReload()
            browserPage?.reload()
            return
        }

        // Don't clear error state immediately - let onStart callback handle it
        // This prevents showing white background before navigation begins
        if let url = failedURL {
            let request = URLRequest(url: url)
            browserPage?.load(request)
        }
    }

    func continueToInsecureSite() {
        let url = failedURL ?? self.url
        guard let host = url.host else { return }
        browserPage?.bypassSSL(for: host)
        clearNavigationError()
        browserPage?.load(URLRequest(url: url))
    }

    var canGoBack: Bool {
        browserPage?.canGoBack ?? false
    }

    var canGoForward: Bool {
        browserPage?.canGoForward ?? false
    }

    var currentPageURL: URL? {
        browserPage?.currentURL
    }

    var pageWindow: NSWindow? {
        browserPage?.window
    }

    func reload() {
        browserPage?.reload()
    }

    func refreshBrowserPageForPrivacySettings() {
        guard isWebViewReady,
              let historyManager,
              let downloadManager,
              let tabManager
        else {
            return
        }

        destroyWebView()
        restoreTransientState(
            historyManager: historyManager,
            downloadManager: downloadManager,
            tabManager: tabManager,
            isPrivate: isPrivate
        )
    }

    func evaluateJavaScript(_ script: String, completion: ((Any?, Error?) -> Void)? = nil) {
        browserPage?.evaluateJavaScript(script, completion: completion)
    }

    func takeSnapshot(
        configuration: BrowserSnapshotConfiguration,
        completion: @escaping (NSImage?, Error?) -> Void
    ) {
        browserPage?.takeSnapshot(configuration: configuration, completion: completion)
    }
}

extension FileManager {
    var faviconDirectory: URL {
        let dir = urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Favicons")
        if !fileExists(atPath: dir.path) {
            try? createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        // swiftlint:disable:next identifier_name
        let r, g, b, a: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
            a = 1.0
        case 8:
            r = Double((int >> 24) & 0xFF) / 255
            g = Double((int >> 16) & 0xFF) / 255
            b = Double((int >> 8) & 0xFF) / 255
            a = Double(int & 0xFF) / 255
        default:
            return nil
        }

        self.init(calibratedRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    func toHex() -> String? {
        guard let color = usingColorSpace(.deviceRGB) else { return nil }
        // swiftlint:disable:next identifier_name
        let r = Int(color.redComponent * 255)
        // swiftlint:disable:next identifier_name
        let g = Int(color.greenComponent * 255)
        // swiftlint:disable:next identifier_name
        let b = Int(color.blueComponent * 255)
        // swiftlint:disable:next identifier_name
        let a = Int(color.alphaComponent * 255)

        return a < 255
            ? String(format: "#%02X%02X%02X%02X", r, g, b, a)
            : String(format: "#%02X%02X%02X", r, g, b)
    }
}
