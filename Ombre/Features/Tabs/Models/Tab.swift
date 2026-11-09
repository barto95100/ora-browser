import AppKit
@preconcurrency import WebKit
import os
import SwiftData
import SwiftUI

private let logger = Logger(category: "Tab")

enum TabType: String, Codable {
    case pinned
    case fav
    case normal
}

// MARK: - Tab

@Model
class Tab: ObservableObject, Identifiable {
    @Attribute(.unique) var id: UUID
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

    /// Published so the sidebar's speaker icon follows playback.
    @Transient @Published var isPlayingMedia: Bool = false
    /// Set while the tab is being closed, so it is not picked as the next tab.
    @Transient var isClosing = false
    @Transient @Published var backgroundColor: Color = .black
    /// The window's managers, owned by the window: weak, or the tab (kept by
    /// `TabManager.activeTab`) would keep its closed window alive.
    @Transient weak var historyManager: HistoryManager?
    @Transient weak var downloadManager: DownloadManager?
    @Transient weak var tabManager: TabManager?
    /// The tab's state in its window (`TabManager.runtimes`), held here too so
    /// views notice when it is made: of the transient properties, only the
    /// published ones are observed.
    @Transient @Published var pageRuntime: TabRuntime?
    @Transient var maybeIsActive = false
    @Transient var isPrivate: Bool = false

    /// The space, optional in the database so deleting a space never leaves a
    /// tab pointing at nothing. Nil only once the tab or its space is deleted:
    /// code that runs later (after an animation, a page callback) reads this,
    /// the rest uses `container`.
    @Relationship(inverse: \TabContainer.tabs) var parentContainer: TabContainer?

    /// The tab's space. Never read it on a deleted tab: see `parentContainer`.
    var container: TabContainer {
        get {
            guard let parentContainer else { preconditionFailure("Tab \(id) has no space: it was deleted") }
            return parentContainer
        }
        set { parentContainer = newValue }
    }

    /// Whether this tab is considered alive (recently accessed)
    @MainActor
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
        self.parentContainer = container
        self.order = order
        self.historyManager = historyManager
        self.downloadManager = downloadManager
        self.tabManager = tabManager
        self.isPrivate = isPrivate
    }

    /// When it was last shown; never shown counts as the oldest.
    var lastAccessedOrDistantPast: Date {
        lastAccessedAt ?? .distantPast
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

    /// The header's color: the page's theme color when it has one (like
    /// Safari's tinted tab bar), else the top of the page, read a second
    /// later once it has drawn (after a load, a switch to the tab, back or
    /// forward); nothing is polled while a page loads.
    @MainActor
    func updateHeaderColor() {
        if let themeColor = browserPage?.themeColor {
            updateBackgroundColor(Color(nsColor: themeColor))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let page = browserPage, page.themeColor == nil else { return }
            pageDelegate?.takeSnapshotAfterLoad(page)
        }
    }

    @MainActor
    func updateHistory() {
        // No space left (the tab is being deleted): nothing to record.
        guard let historyManager, let container = parentContainer else { return }
        let title = title
        let url = url
        let favicon = favicon
        let faviconLocalFile = faviconLocalFile
        Task { @MainActor in
            historyManager.record(
                title: title,
                url: url,
                faviconURL: favicon,
                faviconLocalFile: faviconLocalFile,
                container: container
            )
        }
    }

    @MainActor
    func setupBrowserPageDelegate(for page: BrowserPage) {
        let delegate = TabBrowserPageDelegate()
        delegate.tab = self
        delegate.mediaController = tabManager?.mediaController
        delegate.passwordCoordinator = passwordCoordinator
        page.delegate = delegate
        pageDelegate = delegate
    }

    @MainActor
    func goForward() {
        lastAccessedAt = Date()
        browserPage?.goForward()
        updateHeaderColor()
    }

    @MainActor
    func goBack() {
        lastAccessedAt = Date()
        browserPage?.goBack()
        updateHeaderColor()
    }

    /// A page in this tab's space and privacy mode, with Ombre's scripts and the
    /// space's privacy settings.
    @MainActor
    func makeBrowserPage(isPrivate: Bool) -> BrowserPage {
        let engine = BrowserEngine.shared
        let profile = engine.makeProfile(
            identifier: container.id,
            isPrivate: isPrivate,
            privateSession: tabManager?.privateSessionID
        )
        let privacySettings = SettingsStore.shared.privacySettings(for: container.id)
        let userScripts = OmbreBrowserScripts.userScripts() + BrowserPrivacyService.privacyScripts(
            for: privacySettings,
            spaceID: container.id,
            isPrivate: isPrivate
        )
        return engine.makePage(
            profile: profile,
            configuration: BrowserPageConfiguration.ombreDefault(
                userScripts: userScripts,
                privacySettings: privacySettings,
                enablesWebNotifications: !isPrivate
            ),
            delegate: nil
        )
    }

    /// A page for a window this tab's page opens, linked to it: made with
    /// WebKit's configuration (see `BrowserPage`), in this tab's space.
    @MainActor
    func makeLinkedBrowserPage(
        configuration webKitConfiguration: WKWebViewConfiguration,
        opener: BrowserPage?
    ) -> BrowserPage {
        let privacySettings = SettingsStore.shared.privacySettings(for: container.id)
        let userScripts = OmbreBrowserScripts.userScripts() + BrowserPrivacyService.privacyScripts(
            for: privacySettings,
            spaceID: container.id,
            isPrivate: isPrivate
        )
        return BrowserPage(
            profile: BrowserEngine.shared.makeProfile(
                identifier: container.id,
                isPrivate: isPrivate,
                privateSession: tabManager?.privateSessionID
            ),
            configuration: BrowserPageConfiguration.ombreDefault(
                userScripts: userScripts,
                privacySettings: privacySettings,
                enablesWebNotifications: !isPrivate
            ),
            delegate: nil,
            webKitConfiguration: webKitConfiguration,
            inheritedRuleLists: opener?.spaceContentRuleLists ?? []
        )
    }

    @MainActor
    func restoreTransientState(
        historyManager: HistoryManager,
        downloadManager: DownloadManager,
        tabManager: TabManager,
        isPrivate: Bool
    ) {
        // Avoid double initialization
        if browserPage != nil { return }

        // First: the page takes the window's private session from it, and
        // its state is kept in the window's runtime.
        self.tabManager = tabManager
        if passwordCoordinator == nil {
            passwordCoordinator = PasswordAutofillCoordinator(tab: self)
        }
        let page = makeBrowserPage(isPrivate: isPrivate)
        browserPage = page

        self.historyManager = historyManager
        self.downloadManager = downloadManager
        self.isWebViewReady = false
        self.setupBrowserPageDelegate(for: page)
        self.syncBackgroundColorFromHex()
        WebExtensionsHub.tabOpened(self)
        // Load after a short delay to ensure layout. Not if the page was
        // destroyed (tab closed or unloaded) or replaced in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self, weak page] in
            guard let self, let page, self.browserPage === page else { return }
            self.beginFileAccessIfNeeded()
            let url = if self.type != .normal { self.savedURL } else { self.url }
            page.load(URLRequest(url: url ?? self.url))
            self.isWebViewReady = true
        }
    }

    @MainActor
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
                    if let self, self.browserPage === page {
                        WebExtensionsHub.tabClosed(self)
                    }
                    if self?.browserPage === page {
                        self?.pageDelegate?.dismissDialog()
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

    @MainActor
    func loadURL(_ urlString: String) {
        lastAccessedAt = Date()
        let input = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Try to construct a direct URL (has scheme or valid domain+TLD/IP,
        // or a local file, once Ombre may read it)
        if let directURL = constructURL(from: input) {
            LocalFileAccess.whenReadable(directURL) { [weak self] url in
                // The tab keeps its access to a local file across relaunches.
                if url.isFileURL { self?.keepFileAccess(to: url) }
                self?.browserPage?.load(URLRequest(url: url))
            }
            return
        }

        // 2) Otherwise, a search with the engine chosen for the space (or for
        // all spaces); never another one.
        if let searchURL = SearchEngineService().searchURL(for: input, containerId: container.id) {
            browserPage?.load(URLRequest(url: searchURL))
            return
        }
        logger.error("No search engine makes an address: the search isn't sent")
        let alert = NSAlert()
        alert.messageText = "Ombre couldn't search"
        alert.informativeText = "The search engine chosen in Settings › Search has an invalid address."
        if let window = pageWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @MainActor
    func destroyWebView() {
        cancelPermissionRequest()
        // A new page loads from scratch: nothing left to recover.
        MainActor.assumeIsolated { runtime?.crashRecovery = PageCrashRecoveryPolicy() }
        isReloadingAfterCrash = false
        showsCrashRecoveryNotice = false
        if mediaCaptureState.isCapturing { mediaCaptureState = BrowserMediaCaptureState() }
        if browserPage != nil { WebExtensionsHub.tabClosed(self) }
        // The page's media go with it (closed, unloaded in the background or
        // reloaded for new privacy settings): no event reports it.
        if let mediaController = tabManager?.mediaController {
            mediaController.removeSession(for: id)
        }
        pageDelegate?.dismissDialog()
        browserPage?.teardown()
        browserPage = nil
        pageDelegate = nil
        isWebViewReady = false
        endFileAccess()
        MainActor.assumeIsolated { runtime?.reset() }
    }

    /// The tab's state in its window, if it has one (see `TabRuntime`):
    /// reading it never makes one.
    @MainActor var runtime: TabRuntime? {
        pageRuntime
    }

    /// Shown by the page's error view; only while the tab has a page in an
    /// open window (an error arriving after it went is dropped).
    @MainActor
    func setNavigationError(_ error: Error, for url: URL?) {
        DispatchQueue.main.async {
            guard self.browserPage != nil, let tabManager = self.tabManager, !tabManager.isTornDown else { return }
            tabManager.runtime(for: self).navigationFailed(error, url: url)
        }
    }

    @MainActor
    func clearNavigationError() {
        DispatchQueue.main.async { self.runtime?.clearNavigationFailure() }
    }

    /// The address that failed to load, if the page shows an error.
    @MainActor var failedURL: URL? {
        runtime?.navigationFailure?.url
    }

    @MainActor func retryNavigation() {
        // A crashed page reloads in place, keeping its back/forward history.
        if runtime?.navigationFailure?.error is PageCrashError {
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

    /// Trusts the certificate the page refused, for its host only.
    @MainActor func continueToInsecureSite() {
        let url = failedURL ?? self.url
        guard let host = url.host,
              let error = runtime?.navigationFailure?.error,
              let trust = CertificateException.trust(in: error),
              let digest = CertificateException.digest(of: trust)
        else { return }
        browserPage?.allowCertificate(digest: digest, for: host)
        clearNavigationError()
        browserPage?.load(URLRequest(url: url))
    }

    @MainActor
    var canGoBack: Bool {
        browserPage?.canGoBack ?? false
    }

    @MainActor
    var canGoForward: Bool {
        browserPage?.canGoForward ?? false
    }

    @MainActor
    var currentPageURL: URL? {
        browserPage?.currentURL
    }

    @MainActor
    var pageWindow: NSWindow? {
        browserPage?.window
    }

    @MainActor
    func reload() {
        browserPage?.reload()
    }

    @MainActor
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

    @MainActor
    func evaluateJavaScript(_ script: String, completion: ((Any?, Error?) -> Void)? = nil) {
        browserPage?.evaluateJavaScript(script, completion: completion)
    }

    @MainActor
    func takeSnapshot(
        configuration: BrowserSnapshotConfiguration,
        completion: @escaping @MainActor @Sendable (NSImage?, Error?) -> Void
    ) {
        browserPage?.takeSnapshot(configuration: configuration, completion: completion)
    }
}

extension FileManager {
    var faviconDirectory: URL {
        OmbreDataFolder.subfolder("Favicons", of: OmbreDataFolder.caches)
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

extension Tab {
    /// Another window saved this tab: a fetch refreshed its values without
    /// telling the views reading them. Tells them, without changing anything
    /// (setting the values again would mark the tab as changed here).
    func noteChangedElsewhere() {
        note(\.url)
        note(\.urlString)
        note(\.savedURL)
        note(\.title)
        note(\.favicon)
        note(\.faviconLocalFile)
        note(\.lastAccessedAt)
        note(\.type)
        note(\.order)
        note(\.backgroundColorHex)
        note(\.splitRightTabID)
        note(\.splitFraction)
        note(\.folderID)
        note(\.parentContainer)
    }

    private func note(_ keyPath: KeyPath<Tab, some Any>) {
        _$observationRegistrar.withMutation(of: self, keyPath: keyPath) {}
    }
}
