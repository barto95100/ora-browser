import AppKit
import OSLog
@preconcurrency import WebKit

/// Runs the extensions with WebKit (macOS 15.4+): one controller for the
/// pages of normal windows, the installed extensions (Safari extensions of
/// installed apps), their permissions, and the windows and tabs they see.
/// The controller delegate is in `WebExtensionsManager+Delegate.swift`.
@available(macOS 15.4, *)
@MainActor
final class WebExtensionsManager: NSObject, ObservableObject {
    struct Installed: Identifiable {
        var record: ExtensionRecord
        var context: WKWebExtensionContext?
        var loadError: String?
        var id: String {
            record.id
        }
    }

    /// An extension about to be added (from an app, the Chrome Web Store or
    /// a file), read to show what it asks for.
    @MainActor
    struct Review: Identifiable {
        /// Its id once added (its package is already named after it).
        let id: String
        let source: ExtensionRecord.Source
        /// The app that brings it, for a Safari extension.
        let appName: String?
        let fallbackName: String
        let webExtension: WKWebExtension

        var name: String {
            webExtension.displayName ?? fallbackName
        }

        var originText: String {
            ExtensionRecord(id: id, source: source, name: name, appName: appName).originText
        }

        var permissions: [String] {
            webExtension.requestedPermissions.map(\.rawValue).sorted()
        }

        var sites: [String] {
            webExtension.allRequestedMatchPatterns.map(\.string).sorted()
        }
    }

    enum Failure: LocalizedError {
        case appRemoved
        case nativeMessagingUnsupported
        case noAnchor

        var errorDescription: String? {
            switch self {
            case .appRemoved: "The app that brings this extension isn't installed anymore."
            case .nativeMessagingUnsupported: "Ora can't talk to the extension's app."
            case .noAnchor: "No window to show the popup in."
            }
        }
    }

    static let shared = WebExtensionsManager()
    /// Safari extensions on the App Store (what Safari opens).
    static let appStoreURL = URL(string: "macappstore://apps.apple.com/story/id1377753262")

    let controller: WKWebExtensionController
    @Published private(set) var installed: [Installed] = []
    @Published private(set) var candidates: [SafariExtensionCandidate] = []
    /// Bumped when an extension's button (icon, badge, state) changes.
    @Published private(set) var actionsRevision = 0

    let logger = Logger(subsystem: "com.orabrowser.ora", category: "Extensions")
    /// The button the next popup shows under (see `ExtensionActionButtons`).
    weak var popupAnchor: NSView?

    private let registry = ExtensionRegistry.standard
    private var windows: [ObjectIdentifier: ExtensionWindow] = [:]
    private var tabs: [UUID: ExtensionTab] = [:]
    /// Tabs the extensions were told about (`didOpenTab`).
    private var openTabIDs: Set<UUID> = []
    /// Messages to an extension's app already logged (`id:command`).
    var loggedNativeCommands: Set<String> = []
    /// The extensions' buttons, by extension: a shortcut's popup shows under it.
    let buttonAnchors = NSMapTable<NSString, NSView>.strongToWeakObjects()
    private var keyMonitor: Any?
    private var activeTabIDs: [ObjectIdentifier: UUID] = [:]
    private var isStarted = false
    private var scanTask: Task<Void, Never>?

    override private init() {
        let configuration = WKWebExtensionController.Configuration(identifier: Self.storeIdentifier)
        // The extension's own pages (popup, background) say they are Safari,
        // like Ora's pages: extensions tell browsers apart by the user agent
        // (Bitwarden's popup stops on WebKit's bare one, without "Safari/").
        let pageConfiguration = configuration.webViewConfiguration ?? WKWebViewConfiguration()
        pageConfiguration.applicationNameForUserAgent = SafariUserAgent.current
        configuration.webViewConfiguration = pageConfiguration
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
    }

    /// Where the extensions keep their data, the same at every launch.
    private static var storeIdentifier: UUID {
        let key = "extensions.storeIdentifier"
        if let stored = UserDefaults.standard.string(forKey: key), let identifier = UUID(uuidString: stored) {
            return identifier
        }
        let identifier = UUID()
        UserDefaults.standard.set(identifier.uuidString, forKey: key)
        return identifier
    }

    // MARK: - Launch

    func start() {
        guard !isStarted else { return }
        isStarted = true
        BrowserEngine.shared.webExtensionController = controller
        installed = registry.load().map { Installed(record: $0) }
        for item in installed where item.record.isEnabled {
            Task { await load(id: item.id) }
        }

        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { self.windowBecameKey(window) }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated { self.windowWillClose(window) }
        }
        // What goes wrong in an extension (its background page, its scripts).
        center.addObserver(forName: WKWebExtensionContext.errorsDidUpdateNotification, object: nil, queue: .main) {
            note in
            let context = note.object as? WKWebExtensionContext
            MainActor.assumeIsolated { self.logErrors(of: context) }
        }
        // The extensions' keyboard shortcuts (see `+Commands.swift`).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors run on the main thread; only whether an
            // extension took the key crosses back.
            nonisolated(unsafe) let keyEvent = event
            let handled = MainActor.assumeIsolated { self.handleShortcut(keyEvent) }
            return handled ? nil : event
        }
        // Back from the App Store: a new app may bring an extension.
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.refreshCandidates() }
        }
    }

    // MARK: - Installed extensions

    var loadedContexts: [(record: ExtensionRecord, context: WKWebExtensionContext)] {
        installed.compactMap { item in item.context.map { (record: item.record, context: $0) } }
    }

    /// Looks for Safari extensions in the installed apps, off the main thread.
    func refreshCandidates() {
        scanTask?.cancel()
        scanTask = Task {
            let found = await Task.detached(priority: .utility) { SafariExtensionScanner.scan() }.value
            guard !Task.isCancelled else { return }
            let installedIdentifiers = Set(installed.compactMap(\.record.bundleIdentifier))
            let available = found.filter { !installedIdentifiers.contains($0.bundleIdentifier) }
            if available != candidates { candidates = available }
        }
    }

    /// Reads an extension found in an app, to show what it asks for before
    /// installing it.
    func review(_ candidate: SafariExtensionCandidate) async throws -> Review {
        guard let bundle = Bundle(url: candidate.appexURL) else { throw Failure.appRemoved }
        let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
        return Review(
            id: UUID().uuidString,
            source: .safariApp(appexPath: candidate.appexURL.path, bundleIdentifier: candidate.bundleIdentifier),
            appName: candidate.appName,
            fallbackName: candidate.name,
            webExtension: webExtension
        )
    }

    /// Installs a reviewed extension, with what it asked for; its websites
    /// on all of them, or each asked for the first time (like Safari).
    func install(_ review: Review, allowAllSites: Bool) {
        var record = ExtensionRecord(id: review.id, source: review.source, name: review.name, appName: review.appName)
        record.grantedPermissions = review.permissions
        record.grantedMatchPatterns = review.sites
        record.otherSites = allowAllSites ? .allow : .ask
        installed.append(Installed(record: record))
        save()
        if let bundleIdentifier = record.bundleIdentifier {
            candidates.removeAll { $0.bundleIdentifier == bundleIdentifier }
        }
        run(review.webExtension, id: record.id)
    }

    func setEnabled(_ enabled: Bool, id: String) {
        guard let index = index(of: id), installed[index].record.isEnabled != enabled else { return }
        installed[index].record.isEnabled = enabled
        save()
        if enabled {
            Task { await load(id: id) }
        } else {
            unload(at: index)
        }
    }

    /// Removes the extension and its data.
    func remove(id: String) {
        guard let index = index(of: id) else { return }
        unload(at: index)
        let record = installed.remove(at: index).record
        save()
        if record.bundleIdentifier == nil { ExtensionPackages.remove(path: record.path) }
        let types = WKWebExtensionController.allExtensionDataTypes
        controller.fetchDataRecords(ofTypes: types) { [controller] records in
            let own = records.filter { $0.uniqueIdentifier == id }
            guard !own.isEmpty else { return }
            controller.removeData(ofTypes: types, from: own) {}
        }
        refreshCandidates()
    }

    /// Clicks the extension's button: its popup under `anchor`, or its action.
    func performAction(_ context: WKWebExtensionContext, for tab: Tab?, anchor: NSView?) {
        popupAnchor = anchor
        context.performAction(for: tab.map { adapter(for: $0) })
    }

    func actionDidChange() {
        actionsRevision += 1
    }

    private func load(id: String) async {
        guard let index = index(of: id), installed[index].context == nil else { return }
        let record = installed[index].record
        do {
            let webExtension: WKWebExtension
            if record.bundleIdentifier != nil {
                guard let bundle = Bundle(path: record.path) else { throw Failure.appRemoved }
                webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            } else {
                // Ora's package: a .zip, or a folder.
                let isArchive = record.path.hasSuffix(".zip")
                let package = URL(fileURLWithPath: record.path, isDirectory: !isArchive)
                webExtension = try await WKWebExtension(resourceBaseURL: package)
            }
            run(webExtension, id: id)
        } catch {
            fail(id: id, error)
        }
    }

    private func run(_ webExtension: WKWebExtension, id: String) {
        guard let index = index(of: id), installed[index].record.isEnabled, installed[index].context == nil else {
            return
        }
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = id
        #if DEBUG
            context.isInspectable = true
        #endif
        applyAccess(installed[index].record, to: context)
        do {
            try controller.load(context)
            installed[index].context = context
            installed[index].loadError = nil
            // Tabs opened before it loaded (at launch, before the windows
            // were known): without them, their pages' scripts can't talk to it.
            for tabID in openTabIDs {
                if let adapter = tabs[tabID] { context.didOpenTab(adapter) }
            }
            if let name = webExtension.displayName, name != installed[index].record.name {
                installed[index].record.name = name
                save()
            }
            for error in webExtension.errors {
                logger.warning("\(webExtension.displayName ?? id, privacy: .public): \(error.localizedDescription)")
            }
        } catch {
            fail(id: id, error)
        }
    }

    private func unload(at index: Int) {
        guard let context = installed[index].context else { return }
        try? controller.unload(context)
        installed[index].context = nil
    }

    private func logErrors(of context: WKWebExtensionContext?) {
        guard let context else { return }
        let name = context.webExtension.displayName ?? context.uniqueIdentifier
        for error in context.errors {
            logger.error("\(name, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fail(id: String, _ error: Error) {
        logger.error("Extension \(id, privacy: .public) not loaded: \(error.localizedDescription, privacy: .public)")
        if let index = index(of: id) {
            installed[index].loadError = error.localizedDescription
        }
    }

    /// Changes an installed extension's record, keeps it, and applies its
    /// website access to the running extension at once.
    func updateRecord(id: String, _ change: (inout ExtensionRecord) -> Void) {
        guard let index = index(of: id) else { return }
        change(&installed[index].record)
        save()
        if let context = installed[index].context {
            applyAccess(installed[index].record, to: context)
        }
        actionDidChange()
    }

    func record(for context: WKWebExtensionContext) -> ExtensionRecord? {
        installed.first { $0.id == context.uniqueIdentifier }?.record
    }

    private func index(of id: String) -> Int? {
        installed.firstIndex { $0.id == id }
    }

    private func save() {
        registry.save(installed.map(\.record))
    }

    // MARK: - Windows and tabs

    func adapter(for tab: Tab) -> ExtensionTab {
        if let adapter = tabs[tab.id] { return adapter }
        let adapter = ExtensionTab(tab: tab, manager: self)
        tabs[tab.id] = adapter
        return adapter
    }

    /// A window's loaded tabs: the space it shows first, favorites, pinned
    /// tabs then the others as in the sidebar; then its other spaces' tabs.
    func loadedTabs(of tabManager: TabManager) -> [Tab] {
        let activeContainerID = tabManager.activeContainer?.id
        func rank(_ type: TabType) -> Int {
            switch type {
            case .fav: 0
            case .pinned: 1
            case .normal: 2
            }
        }
        return tabs.values
            .compactMap(\.tab)
            .filter { openTabIDs.contains($0.id) && $0.tabManager === tabManager }
            .filter { $0.browserPage != nil && !$0.isClosing }
            .sorted { lhs, rhs in
                let lhsActive = lhs.container.id == activeContainerID
                let rhsActive = rhs.container.id == activeContainerID
                if lhsActive != rhsActive { return lhsActive }
                if lhs.container.id != rhs.container.id {
                    return lhs.container.createdAt < rhs.container.createdAt
                }
                if rank(lhs.type) != rank(rhs.type) { return rank(lhs.type) < rank(rhs.type) }
                return lhs.order > rhs.order
            }
    }

    func window(for tabManager: TabManager) -> ExtensionWindow? {
        windows.values.first { $0.tabManager === tabManager }
    }

    /// Normal windows, front to back.
    var orderedWindows: [ExtensionWindow] {
        NSApp.orderedWindows.compactMap { windows[ObjectIdentifier($0)] }
    }

    var focusedWindow: ExtensionWindow? {
        NSApp.keyWindow.flatMap { windows[ObjectIdentifier($0)] } ?? orderedWindows.first
    }

    /// The front normal window: what Ora opens itself (options pages) never
    /// goes to a private window.
    var focusedNormalWindow: ExtensionWindow? {
        if let window = focusedWindow, !window.isPrivateWindow { return window }
        return orderedWindows.first { !$0.isPrivateWindow }
    }

    func registerWindow(_ window: NSWindow, tabManager: TabManager, isPrivate: Bool) {
        let key = ObjectIdentifier(window)
        if let existing = windows[key] {
            existing.tabManager = tabManager
            return
        }
        let adapter = ExtensionWindow(window: window, tabManager: tabManager, isPrivate: isPrivate, manager: self)
        windows[key] = adapter
        controller.didOpenWindow(adapter)
        // Its tabs opened before the window was known: told again, now that
        // they have a window.
        for tab in loadedTabs(of: tabManager) {
            controller.didOpenTab(self.adapter(for: tab))
        }
        if window.isKeyWindow { controller.didFocusWindow(adapter) }
    }

    func tabOpened(_ tab: Tab) {
        guard openTabIDs.insert(tab.id).inserted else { return }
        controller.didOpenTab(adapter(for: tab))
    }

    func tabClosed(_ tab: Tab) {
        guard openTabIDs.remove(tab.id) != nil, let adapter = tabs.removeValue(forKey: tab.id) else { return }
        controller.didCloseTab(adapter, windowIsClosing: false)
    }

    func activeTabChanged(in tabManager: TabManager) {
        guard let window = window(for: tabManager), let tab = tabManager.activeTab, tab.browserPage != nil,
              let windowKey = window.window.map(ObjectIdentifier.init)
        else { return }
        let previous = activeTabIDs[windowKey].flatMap { tabs[$0] }
        guard previous?.tab?.id != tab.id else { return }
        tabOpened(tab)
        activeTabIDs[windowKey] = tab.id
        controller.didActivateTab(adapter(for: tab), previousActiveTab: previous)
    }

    func tabChanged(_ tab: Tab, url: Bool, title: Bool, loading: Bool) {
        guard openTabIDs.contains(tab.id) else { return }
        var properties: WKWebExtension.TabChangedProperties = []
        if url { properties.insert(.URL) }
        if title { properties.insert(.title) }
        if loading { properties.insert(.loading) }
        guard !properties.isEmpty else { return }
        controller.didChangeTabProperties(properties, for: adapter(for: tab))
        // Another website in front: the buttons' dot (access asked) follows.
        if url, tab.tabManager?.activeTab?.id == tab.id { actionDidChange() }
    }

    private func windowBecameKey(_ window: NSWindow?) {
        guard let window, let adapter = windows[ObjectIdentifier(window)] else { return }
        controller.didFocusWindow(adapter)
    }

    private func windowWillClose(_ window: NSWindow?) {
        guard let window, let adapter = windows.removeValue(forKey: ObjectIdentifier(window)) else { return }
        activeTabIDs[ObjectIdentifier(window)] = nil
        controller.didCloseWindow(adapter)
    }
}
