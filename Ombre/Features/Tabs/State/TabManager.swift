import os
import SwiftData
import SwiftUI

private let logger = Logger(category: "TabManager")

// MARK: - Tab Manager

private struct ClosedTabSnapshot {
    let id: UUID
    let containerID: UUID
    let url: URL
    let savedURL: URL?
    let title: String
    let favicon: URL?
    let faviconLocalFile: URL?
    let createdAt: Date
    let lastAccessedAt: Date?
    let type: TabType
    let order: Int
    let backgroundColorHex: String
    let isPrivate: Bool

    init(tab: Tab) {
        id = tab.id
        containerID = tab.container.id
        url = tab.url
        savedURL = tab.savedURL
        title = tab.title
        favicon = tab.favicon
        faviconLocalFile = tab.faviconLocalFile
        createdAt = tab.createdAt
        lastAccessedAt = tab.lastAccessedAt
        type = tab.type
        order = tab.order
        backgroundColorHex = tab.backgroundColorHex
        isPrivate = tab.isPrivate
    }
}

@MainActor
// swiftlint:disable:next type_body_length
class TabManager: ObservableObject {
    @Published var activeContainer: TabContainer?
    @Published var activeTab: Tab?
    /// A link previewed over the active tab, see `TabManager+Peek.swift`.
    @Published var peek: PeekPage?
    /// Left tab of a split asked for with New Split View, waiting for the tab
    /// opened from the launcher (see `TabManager+Split.swift`).
    var pendingSplitLeftTabID: UUID?
    /// Folder whose name the sidebar is editing (a new folder, or Rename).
    @Published var renamingFolderID: UUID?
    /// Tab (or folder) being dragged in the sidebar: the page then offers
    /// split zones (see `SplitDropOverlay`).
    @Published var draggingTabID: UUID?
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    let mediaController: MediaController
    /// The window's download manager, shown by its Downloads panel. Tabs must
    /// all use it: a separate instance records downloads the panel never sees.
    let downloadManager: DownloadManager
    /// The window's history manager. Tabs restored or opened without one use
    /// it, rather than a fallback instance of their own.
    let historyManager: HistoryManager
    /// The window's undo manager (Edit › Undo, ⌘Z), set by the window.
    weak var windowUndoManager: UndoManager?

    var recentTabs: [Tab] {
        guard let container = activeContainer else { return [] }
        return Array(container.tabs
            .sorted { ($0.lastAccessedAt ?? Date.distantPast) > ($1.lastAccessedAt ?? Date.distantPast) }
            .prefix(SettingsStore.shared.maxRecentTabs)
        )
    }

    /// Note: Could be made injectable via init parameter if preferred
    let tabSearchingService: TabSearchingProviding

    /// Stopped with the window, see `tearDown()`.
    var cleanupTimer: Timer?
    /// The window closed: its pages are gone and must not come back.
    var isTornDown = false
    /// macOS memory pressure events, see `TabManager+MemoryPressure.swift`.
    var memoryPressureSource: DispatchSourceMemoryPressure?
    private var recentlyClosedTabs: [ClosedTabSnapshot] = []
    private let maxRecentlyClosedTabs = 5

    init(
        modelContainer: ModelContainer,
        modelContext: ModelContext,
        mediaController: MediaController,
        downloadManager: DownloadManager,
        historyManager: HistoryManager,
        tabSearchingService: TabSearchingProviding = TabSearchingService()
    ) {
        self.modelContainer = modelContainer
        self.modelContext = modelContext
        self.mediaController = mediaController
        self.downloadManager = downloadManager
        self.historyManager = historyManager
        self.tabSearchingService = tabSearchingService
        mediaController.tabManager = self

        // No undo manager on the model context: it recorded every tab, history
        // and download change, never emptied, and undoing them could unset a
        // tab's container and crash (upstream issue #161). Closing a tab is
        // undone through the window's undo manager instead.
        initializeActiveContainerAndTab()

        // Start automatic cleanup timer (every minute)
        startCleanupTimer()
        startMemoryPressureMonitoring()
    }

    // MARK: - Public API's

    func search(_ text: String) -> [Tab] {
        tabSearchingService.search(
            text,
            activeContainer: activeContainer,
            modelContext: modelContext
        )
    }

    func openFromEngine(
        engineName: SearchEngineID,
        query: String,
        historyManager: HistoryManager,
        isPrivate: Bool
    ) {
        if let url = SearchEngineService().getSearchURLForEngine(
            engineName: engineName,
            query: query
        ) {
            openTab(url: url, historyManager: historyManager, isPrivate: isPrivate)
        }
    }

    func isActive(_ tab: Tab) -> Bool {
        if let activeTab = self.activeTab {
            return activeTab.id == tab.id
        }
        return false
    }

    func togglePinTab(_ tab: Tab) {
        if tab.type == .pinned {
            tab.type = .normal
            tab.savedURL = nil
            tab.folderID = nil
        } else {
            tab.type = .pinned
            tab.savedURL = tab.url
        }

        modelContext.saveOrLog("toggle pin tab")
    }

    func toggleFavTab(_ tab: Tab) {
        tab.folderID = nil
        if tab.type == .fav {
            tab.type = .normal
            tab.savedURL = nil
        } else {
            tab.type = .fav
            tab.savedURL = tab.url
        }

        modelContext.saveOrLog("toggle favorite tab")
    }

    // MARK: - Container Public API's

    func moveTabToContainer(_ tab: Tab, toContainer: TabContainer) {
        separateSplit(containing: tab, save: false)
        tab.folderID = nil
        tab.container = toContainer
        modelContext.saveOrLog("move tab to space")
    }

    private func initializeActiveContainerAndTab() {
        // Ensure containers are fetched
        let containers = fetchContainers()

        // Get the last accessed container
        if let lastAccessedContainer = containers.first {
            activeContainer = lastAccessedContainer
            // Get the last accessed tab from the active container
            if let lastAccessedTab = lastAccessedContainer.tabs
                .sorted(by: { ($0.lastAccessedAt ?? Date.distantPast) > ($1.lastAccessedAt ?? Date.distantPast) })
                .first
            {
                activeTab = lastAccessedTab
                activeTab?.maybeIsActive = true
            }
        } else {
            let newContainer = createContainer()
            activeContainer = newContainer
        }
    }

    @discardableResult
    func createContainer(name: String = "Default", emoji: String = "•") -> TabContainer {
        let newContainer = TabContainer(name: name, emoji: emoji)
        newContainer.order = nextContainerOrder()
        modelContext.insert(newContainer)
        activeContainer = newContainer
        self.activeTab = nil
        modelContext.saveOrLog("create space")
        PrivacyDefaults.applyToNewSpace(newContainer.id)
        //        _ = fetchContainers() // Refresh containers
        return newContainer
    }

    /// The order of a new space: after all the others.
    func nextContainerOrder() -> Int {
        var descriptor = FetchDescriptor<TabContainer>(sortBy: [SortDescriptor(\.order, order: .reverse)])
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor))?.first?.order ?? -1) + 1
    }

    func renameContainer(_ container: TabContainer, name: String, emoji: String) {
        container.name = name
        container.emoji = emoji
        modelContext.saveOrLog("rename space")
    }

    /// Deletes the space at once (it can't be used half deleted), then cleans
    /// up what it leaves outside the database: passwords, browsing time,
    /// focus settings and website data. Each cleanup step goes on when
    /// another fails. Returns the cleanup, for the tests.
    @discardableResult
    func deleteContainer(_ container: TabContainer) -> Task<Void, Never> {
        let containerId = container.id
        if let persistedContainer = fetchContainer(id: containerId) {
            // A Peek opened from the space uses its data store.
            if let peek, persistedContainer.tabs.contains(where: { $0.id == peek.openerTabID }) {
                closePeek()
            }
            let wasActiveContainer = activeContainer?.id == containerId
            prepareForContainerDeletion(isActiveContainer: wasActiveContainer)
            deleteContainerContents(persistedContainer)

            // Save child deletions before deleting the container: SwiftData
            // could fail when the parent and children went in the same save.
            modelContext.saveOrLog("delete space contents")

            if let containerToDelete = fetchContainer(id: containerId) {
                modelContext.delete(containerToDelete)
                modelContext.saveOrLog("delete space")
            }
            activateFallbackContainerIfNeeded(afterDeletingActiveContainer: wasActiveContainer)
        }
        SettingsStore.shared.removeContainerSettings(for: containerId)

        return Task { @MainActor in
            do {
                try PasswordManagerService.shared.deleteEntries(for: containerId)
            } catch {
                logger.error("Deleting the space's passwords failed: \(error.localizedDescription, privacy: .public)")
            }
            BrowsingTimeStore.shared.delete(spaceID: containerId)
            FocusSettings.shared.removeSpace(containerId)
            // Its website data, then its store on disk.
            await PrivacyService.clearAllWebsiteData(for: containerId)
            await BrowserEngine.shared.removeProfile(identifier: containerId)
        }
    }

    func activateContainer(_ container: TabContainer, activateLastAccessedTab: Bool = true) {
        activeContainer = container
        container.lastAccessedAt = Date()

        // Set the most recently accessed tab in the container
        if let lastAccessedTab = container.tabs
            .sorted(by: { $0.lastAccessedAt ?? Date() > $1.lastAccessedAt ?? Date() }).first,
           lastAccessedTab.isWebViewReady
        {
            activeTab?.maybeIsActive = false
            activeTab = lastAccessedTab
            activeTab?.maybeIsActive = true
            lastAccessedTab.lastAccessedAt = Date()
        } else {
            activeTab = nil
        }

        modelContext.saveOrLog("activate space")
    }

    // MARK: - Tab Public API's

    func addTab(
        title: String = "Untitled",
        // Will Always Work
        url: URL = URL(string: "about:blank")!,
        container: TabContainer,
        favicon: URL? = nil,
        historyManager: HistoryManager? = nil,
        downloadManager: DownloadManager? = nil,
        isPrivate: Bool
    ) -> Tab {
        let cleanHost: String? = {
            guard let host = url.host else { return nil }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }()
        let newTab = Tab(
            url: url,
            title: cleanHost ?? "New Tab",
            favicon: favicon,
            container: container,
            type: .normal,
            isPlayingMedia: false,
            order: container.tabs.count + 1,
            historyManager: historyManager,
            downloadManager: downloadManager,
            tabManager: self,
            isPrivate: isPrivate
        )
        modelContext.insert(newTab)
        container.tabs.append(newTab)
        activeTab?.maybeIsActive  = false
        activeTab = newTab
        activeTab?.maybeIsActive  = true
        newTab.lastAccessedAt = Date()
        container.lastAccessedAt = Date()

        // Initialize the WebView for the new active tab
        newTab.restoreTransientState(
            historyManager: historyManager ?? self.historyManager,
            downloadManager: downloadManager ?? self.downloadManager,
            tabManager: self,
            isPrivate: isPrivate
        )

        modelContext.saveOrLog("add tab")
        return newTab
    }

    @discardableResult
    func openTab(
        url: URL,
        historyManager: HistoryManager,
        downloadManager: DownloadManager? = nil,
        focusAfterOpening: Bool = true,
        isPrivate: Bool,
        loadSilently: Bool = false
    ) -> Tab? {
        if let container = activeContainer {
            if let (title, faviconURL) = Self.initialTitleAndFavicon(for: url) {
                let newTab = Tab(
                    url: url,
                    title: title,
                    favicon: faviconURL,
                    container: container,
                    type: .normal,
                    isPlayingMedia: false,
                    order: container.tabs.count + 1,
                    historyManager: historyManager,
                    downloadManager: downloadManager,
                    tabManager: self,
                    isPrivate: isPrivate
                )
                modelContext.insert(newTab)
                container.tabs.append(newTab)

                if focusAfterOpening {
                    completePendingSplit(with: newTab)
                    activateTab(newTab)
                }
                if focusAfterOpening || loadSilently {
                    // Initialize the WebView for the new active tab
                    newTab.restoreTransientState(
                        historyManager: historyManager,
                        downloadManager: downloadManager ?? self.downloadManager,
                        tabManager: self,
                        isPrivate: isPrivate
                    )
                }

                container.lastAccessedAt = Date()
                modelContext.saveOrLog("open tab")
                return newTab
            }
        }
        return nil
    }

    /// Placeholder title and favicon shown until the page reports its own:
    /// the host for web pages, the file name for local files (which have no
    /// host). Returns nil for URLs a tab cannot show.
    static func initialTitleAndFavicon(for url: URL) -> (title: String, favicon: URL?)? {
        if let host = url.host, !host.isEmpty {
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return (cleanHost, FaviconService.shared.faviconURL(for: host))
        }
        if url.isFileURL {
            return (url.lastPathComponent, nil)
        }
        return nil
    }

    func switchSections(from: Tab, toTab: Tab) {
        from.switchSections(from: from, to: toTab)
        modelContext.saveOrLog("switch tab section")
    }

    func closeTab(tab: Tab, shouldTrackForRestore: Bool = true) {
        // Already being closed (a double click): once is enough.
        guard !tab.isClosing else { return }
        tab.isClosing = true
        // Closing one side of a split shows the other side alone.
        let partner = splitPartner(of: tab)
        separateSplit(containing: tab, save: false)
        // If the closed tab was active, select another tab
        if self.activeTab?.id == tab.id {
            if let partner {
                self.activateTab(partner)
            } else if let nextTab = tab.container.tabs
                .filter({ $0.id != tab.id && $0.isWebViewReady && !$0.isClosing })
                .sorted(by: { $0.lastAccessedAt ?? Date.distantPast > $1.lastAccessedAt ?? Date.distantPast })
                .first
            {
                self.activateTab(nextTab)

                //            } else if let nextContainer = containers.first(where: { $0.id != tab.container.id }) {
                //                self.activateContainer(nextContainer)
                //
            } else {
                self.activeTab = nil
            }
        } else {
            self.activeTab = activeTab
        }
        // Make sure the tab now shown is loaded. It used to be skipped when the
        // closed tab had never been loaded (it had no managers to lend).
        if let nextTab = activeTab {
            nextTab.restoreTransientState(
                historyManager: nextTab.historyManager ?? historyManager,
                downloadManager: nextTab.downloadManager ?? downloadManager,
                tabManager: self,
                isPrivate: nextTab.isPrivate
            )
        }
        if shouldTrackForRestore, tab.type == .normal {
            trackRecentlyClosedTab(tab)
        }
        tab.stopMedia { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard tab.isClosing else {
                    // ⌘Z brought it back meanwhile (see `restoreLastTab`), but
                    // its page was torn down: load it again.
                    self.reloadCancelledClose(of: tab)
                    return
                }
                if tab.type == .normal {
                    self.modelContext.delete(tab)
                } else {
                    tab.isWebViewReady = false
                    tab.destroyWebView()
                    // Kept in the sidebar: it can be shown again.
                    tab.isClosing = false
                }
                self.mediaController.removeSession(for: tab.id)
                self.modelContext.saveOrLog("close tab")
            }
        }
        self.activeTab?.maybeIsActive = true
    }

    func closeActiveTab() {
        // ⌘W closes Peek first, like Arc.
        if peek != nil {
            closePeek()
        } else if let tab = activeTab {
            closeTab(tab: tab)
        } else {
            NSApp.keyWindow?.close()
        }
    }

    func restoreLastTab() {
        guard let snapshot = recentlyClosedTabs.popLast() else { return }
        // Still being closed (its media is stopping): ⌘Z cancels the close.
        // A new tab would share its id, which is unique.
        if let closing = closingTab(id: snapshot.id) {
            closing.isClosing = false
            activateTab(closing)
            return
        }
        let container = fetchContainers()
            .first(where: { $0.id == snapshot.containerID }) ?? activeContainer ?? createContainer()

        shiftRestoredTabOrders(in: container, restoring: snapshot)

        let restoredTab = Tab(
            id: snapshot.id,
            url: snapshot.url,
            title: snapshot.title,
            favicon: snapshot.favicon,
            container: container,
            type: snapshot.type,
            order: snapshot.order,
            tabManager: self,
            isPrivate: snapshot.isPrivate
        )
        restoredTab.savedURL = snapshot.savedURL
        restoredTab.faviconLocalFile = snapshot.faviconLocalFile
        restoredTab.createdAt = snapshot.createdAt
        restoredTab.lastAccessedAt = snapshot.lastAccessedAt
        restoredTab.backgroundColorHex = snapshot.backgroundColorHex

        modelContext.insert(restoredTab)
        container.tabs.append(restoredTab)
        activateTab(restoredTab)
        modelContext.saveOrLog("restore last tab")
    }

    func activateTab(_ tab: Tab) {
        // Toggle Picture-in-Picture on tab switch
        togglePiPOnSwitch(to: tab)
        let previousTab = activeTab

        // Activate the tab
        activeTab?.maybeIsActive = false
        activeTab = tab
        activeTab?.maybeIsActive = true
        tab.lastAccessedAt = Date()
        activeContainer = tab.container
        tab.container.lastAccessedAt = Date()

        // Lazy load WebView if not ready
        if !tab.isWebViewReady {
            tab.restoreTransientState(
                historyManager: tab.historyManager ?? historyManager,
                downloadManager: tab.downloadManager ?? self.downloadManager,
                tabManager: self,
                isPrivate: tab.isPrivate
            )
        }
        if let partner = splitPartner(of: tab) {
            loadIfNeeded(partner)
        }
        focusPageIfSplit(tab, previous: previousTab)
        tab.updateHeaderColor()
        modelContext.saveOrLog("activate tab")
    }

    /// Clean up old tabs that haven't been accessed recently to preserve memory
    func cleanupOldTabs() {
        let timeout = SettingsStore.shared.tabAliveTimeout
        // Skip cleanup if set to "Never" (365 days)
        guard timeout < 365 * 24 * 60 * 60 else { return }

        let allContainers = fetchContainers()
        for container in allContainers {
            for tab in container.tabs {
                // A tab in a call keeps its page, like one playing media.
                if !tab.isAlive, tab.isWebViewReady, !isShown(tab), !tab.isPlayingMedia,
                   !tab.mediaCaptureState.isCapturing, tab.type == .normal
                {
                    tab.destroyWebView()
                }
            }
        }
    }

    /// Completely remove old normal tabs that haven't been accessed for a long time
    func removeOldTabs() {
        let cutoffDate = Date().addingTimeInterval(-SettingsStore.shared.tabRemovalTimeout)
        let allContainers = fetchContainers()

        for container in allContainers {
            for tab in container.tabs {
                if let lastAccessed = tab.lastAccessedAt,
                   lastAccessed < cutoffDate,
                   !isShown(tab),
                   !tab.isPlayingMedia,
                   !tab.mediaCaptureState.isCapturing,
                   tab.type == .normal
                {
                    closeTab(tab: tab, shouldTrackForRestore: false)
                }
            }
        }
    }

    /// Remove tabs in containers that have a per-space autoClearTabsAfter setting
    func autoClearContainerTabs() {
        let settings = SettingsStore.shared
        let allContainers = fetchContainers()

        for container in allContainers {
            let policy = settings.autoClearTabsAfter(for: container.id)
            guard let timeout = policy.seconds else { continue }

            let cutoffDate = Date().addingTimeInterval(-timeout)
            for tab in container.tabs {
                if let lastAccessed = tab.lastAccessedAt,
                   lastAccessed < cutoffDate,
                   !isShown(tab),
                   !tab.isPlayingMedia,
                   !tab.mediaCaptureState.isCapturing,
                   tab.type == .normal
                {
                    closeTab(tab: tab)
                }
            }
        }
    }

    /// Start the automatic cleanup timer
    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.cleanupOldTabs()
                self?.removeOldTabs()
                self?.autoClearContainerTabs()
            }
        }
    }

    deinit {
        cleanupTimer?.invalidate()
        memoryPressureSource?.cancel()
    }

    /// Activate a tab by its persistent id. If the tab is in a
    /// different container, also activate that container.
    func activateTab(id: UUID) {
        let allContainers = fetchContainers()
        for container in allContainers {
            if let tab = container.tabs.first(where: { $0.id == id }) {
                activateContainer(container)
                activateTab(tab)
                return
            }
        }
    }

    func selectTabAtIndex(_ index: Int) {
        guard let container = activeContainer else { return }

        // Match the sidebar ordering: favorites, then pinned, then normal tabs
        // All sorted by order in descending order
        let favoriteTabs = container.tabs
            .filter { $0.type == .fav }
            .sorted(by: { $0.order > $1.order })

        // Tabs of closed folders are hidden.
        let pinnedTabs = container.visiblePinnedTabs(activeTabID: activeTab?.id)

        // The right side of a split of normal tabs shares its left side's row.
        let splitRightTabIDs = splitRows(in: container).hidden
        let normalTabs = container.tabs
            .filter { $0.type == .normal && !splitRightTabIDs.contains($0.id) }
            .sorted(by: { $0.order > $1.order })

        // Combine all tabs in the same order as the sidebar
        let allTabs = favoriteTabs + pinnedTabs + normalTabs

        // Handle special case: Command+9 selects the last tab
        let targetIndex = (index == 9) ? allTabs.count - 1 : index - 1

        // Validate index is within bounds
        guard targetIndex >= 0, targetIndex < allTabs.count else { return }

        let targetTab = allTabs[targetIndex]
        activateTab(targetTab)
    }

    private func fetchContainers() -> [TabContainer] {
        do {
            let descriptor = FetchDescriptor<TabContainer>(sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)])
            return try modelContext.fetch(descriptor)
        } catch {
            // Failed to fetch containers
        }
        return []
    }

    func duplicateTab(_ tab: Tab) {
        // Create a new tab using the existing openTab method
        // A tab never loaded since launch has no history manager yet.
        guard let newTab = openTab(
            url: tab.url,
            historyManager: tab.historyManager ?? historyManager,
            downloadManager: tab.downloadManager,
            focusAfterOpening: false,
            isPrivate: tab.isPrivate,
            loadSilently: true
        ) else { return }
        // Right after the original, in the same section (a new tab's order
        // says nothing about its place: it may be below the original's).
        tab.container.placeTab(newTab, after: tab)
        modelContext.saveOrLog("duplicate tab")
    }

    func refreshPrivacySettings(for containerId: UUID) {
        guard let container = fetchContainer(id: containerId) else { return }

        let loadedTabs = container.tabs.filter(\.isWebViewReady)
        guard !loadedTabs.isEmpty else { return }

        for tab in loadedTabs {
            tab.refreshBrowserPageForPrivacySettings()
        }
    }

    private func trackRecentlyClosedTab(_ tab: Tab) {
        recentlyClosedTabs.append(ClosedTabSnapshot(tab: tab))
        if recentlyClosedTabs.count > maxRecentlyClosedTabs {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - maxRecentlyClosedTabs)
        }

        // ⌘Z outside a text field reopens it, like Arc and Safari
        // ("Undo Close Tab"); text fields keep undoing typing first.
        windowUndoManager?.registerUndo(withTarget: self) { manager in
            MainActor.assumeIsolated {
                manager.restoreLastTab()
            }
        }
        windowUndoManager?.setActionName("Close Tab")
    }

    private func shiftRestoredTabOrders(in container: TabContainer, restoring snapshot: ClosedTabSnapshot) {
        for tab in container.tabs where tab.type == snapshot.type && tab.order >= snapshot.order {
            tab.order += 1
        }
    }
}

private extension TabManager {
    func reloadCancelledClose(of tab: Tab) {
        guard tab.browserPage == nil else { return }
        tab.isWebViewReady = false
        if activeTab?.id == tab.id {
            activateTab(tab)
        }
    }

    func closingTab(id: UUID) -> Tab? {
        let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first { $0.isClosing }
    }

    func fetchContainer(id: UUID) -> TabContainer? {
        let descriptor = FetchDescriptor<TabContainer>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            return nil
        }
    }

    func prepareForContainerDeletion(isActiveContainer: Bool) {
        guard isActiveContainer else { return }

        activeTab?.maybeIsActive = false
        activeTab = nil
        activeContainer = nil
    }

    func deleteContainerContents(_ container: TabContainer) {
        for tab in Array(container.tabs) {
            if tab.isWebViewReady {
                tab.destroyWebView()
            }
            mediaController.removeSession(for: tab.id)
            modelContext.delete(tab)
        }

        for folder in Array(container.folders) {
            modelContext.delete(folder)
        }
        // The space's history goes with it (cascade).
    }

    func activateFallbackContainerIfNeeded(afterDeletingActiveContainer wasActiveContainer: Bool) {
        guard wasActiveContainer else { return }

        if let nextContainer = fetchContainers().first {
            activateContainer(nextContainer)
        } else {
            _ = createContainer()
        }
    }
}
