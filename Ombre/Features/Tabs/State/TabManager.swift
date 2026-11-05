import SwiftData
import SwiftUI

@MainActor
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
    /// The window's private session (used by private windows only).
    let privateSessionID = UUID()

    /// Note: Could be made injectable via init parameter if preferred
    let tabSearchingService: TabSearchingProviding

    /// The window closed: its pages are gone and must not come back.
    var isTornDown = false
    /// macOS memory pressure events, see `TabManager+MemoryPressure.swift`.
    var memoryPressureSource: DispatchSourceMemoryPressure?
    /// Closed tabs ⌘Z brings back, see `TabManager+ClosedTabs.swift`.
    var recentlyClosedTabs: [ClosedTabSnapshot] = []
    let maxRecentlyClosedTabs = 5

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

        // Old tabs unloaded and closed with the other windows' (one timer).
        TabCleaner.shared.register(self)
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

    // MARK: - Tabs

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
                let newTab = makeTab(
                    url: url,
                    title: title,
                    // A private tab loads no icon from outside its page (the
                    // shared URL cache would keep it on the disk).
                    favicon: isPrivate ? nil : faviconURL,
                    in: container,
                    isPrivate: isPrivate,
                    historyManager: historyManager,
                    downloadManager: downloadManager
                )

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

    /// A tab made active and loaded at once (the Arc import).
    func addTab(
        title: String = "Untitled",
        url: URL,
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
        let newTab = makeTab(
            url: url,
            title: cleanHost ?? "New Tab",
            favicon: favicon,
            in: container,
            isPrivate: isPrivate,
            historyManager: historyManager,
            downloadManager: downloadManager
        )
        activeTab?.maybeIsActive = false
        activeTab = newTab
        activeTab?.maybeIsActive = true
        newTab.lastAccessedAt = Date()
        container.lastAccessedAt = Date()

        newTab.restoreTransientState(
            historyManager: historyManager ?? self.historyManager,
            downloadManager: downloadManager ?? self.downloadManager,
            tabManager: self,
            isPrivate: isPrivate
        )

        modelContext.saveOrLog("add tab")
        return newTab
    }

    /// The one way a tab is made: added to its space, in its section's order.
    @discardableResult
    func makeTab(
        id: UUID = UUID(),
        url: URL,
        title: String,
        favicon: URL? = nil,
        type: TabType = .normal,
        order: Int? = nil,
        in container: TabContainer,
        isPrivate: Bool,
        historyManager: HistoryManager? = nil,
        downloadManager: DownloadManager? = nil
    ) -> Tab {
        let tab = Tab(
            id: id,
            url: url,
            title: title,
            favicon: favicon,
            container: container,
            type: type,
            // On top of its section; `tabs.count + 1` could equal an
            // existing order after a close.
            order: order ?? container.topOrder(of: type),
            historyManager: historyManager,
            downloadManager: downloadManager,
            tabManager: self,
            isPrivate: isPrivate
        )
        modelContext.insert(tab)
        container.tabs.append(tab)
        return tab
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
                .sorted(by: { $0.lastAccessedOrDistantPast > $1.lastAccessedOrDistantPast })
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

    deinit {
        memoryPressureSource?.cancel()
    }

    /// Activate a tab by its persistent id. If the tab is in a
    /// different container, also activate that container.
    func activateTab(id: UUID) {
        let allContainers = fetchContainers()
        for container in allContainers {
            // Its space with it (not the space's last tab first).
            if let tab = container.tabs.first(where: { $0.id == id }) {
                activateTab(tab)
                return
            }
        }
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
}
