import Foundation
import Inject
import SwiftData
import SwiftUI

final class PrivacyMode: ObservableObject {
    @Published var isPrivate: Bool

    init(isPrivate: Bool) {
        self.isPrivate = isPrivate
    }
}

struct OraRoot: View {
    @StateObject private var appState = AppState()
    @StateObject private var keyModifierListener = KeyModifierListener()
    @StateObject private var mediaController: MediaController
    @StateObject private var tabManager: TabManager
    @StateObject private var historyManager: HistoryManager
    @StateObject private var downloadManager: DownloadManager
    @StateObject private var privacyMode: PrivacyMode
    @StateObject private var sidebarManager = SidebarManager()
    @StateObject private var toolbarManager = ToolbarManager()
    @StateObject private var dialogManager = DialogManager()
    private let toastManager = ToastManager.shared

    @ObserveInjection var inject

    let tabContext: ModelContext
    let historyContext: ModelContext
    let downloadContext: ModelContext
    @State private var window: NSWindow?

    init(isPrivate: Bool = false) {
        _privacyMode = StateObject(wrappedValue: PrivacyMode(isPrivate: isPrivate))

        let container: ModelContainer
        let modelContext: ModelContext
        do {
            container = try ModelConfiguration.createOraContainer(isPrivate: isPrivate)
            modelContext = ModelContext(container)
        } catch {
            deleteSwiftDataStore("OraData.sqlite")
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        self.tabContext = modelContext
        self.downloadContext = modelContext
        self.historyContext = modelContext
        let history = HistoryManager(modelContainer: container, modelContext: modelContext)
        _historyManager = StateObject(wrappedValue: history)

        let media = MediaController()
        _mediaController = StateObject(wrappedValue: media)

        let downloads = DownloadManager(modelContainer: container, modelContext: modelContext)
        _downloadManager = StateObject(wrappedValue: downloads)

        _tabManager = StateObject(
            wrappedValue: TabManager(
                modelContainer: container,
                modelContext: modelContext,
                mediaController: media,
                downloadManager: downloads,
                historyManager: history
            )
        )
    }

    var body: some View {
        BrowserView()
            .sheet(isPresented: $appState.showImport) { BrowserImportSheet() }
            .background(WindowReader(window: $window))
            // Browsing time: the page in front changed.
            .onChange(of: tabManager.activeTab?.id) {
                BrowsingTimeTracker.shared.refresh()
                WebExtensionsHub.activeTabChanged(in: tabManager)
            }
            .onChange(of: tabManager.activeTab?.url) { BrowsingTimeTracker.shared.refresh() }
            .background(
                WindowAccessor(
                    isFullscreen: Binding(
                        get: { appState.isFullscreen },
                        set: { newValue in appState.isFullscreen = newValue }
                    )
                )
            )
            .environment(\.window, window)
            .environmentObject(appState)
            .environmentObject(tabManager)
            .environmentObject(historyManager)
            .environmentObject(mediaController)
            .environmentObject(keyModifierListener)
            .environmentObject(CustomKeyboardShortcutManager.shared)
            .environmentObject(AppearanceManager.shared)
            .environmentObject(downloadManager)
            .environmentObject(UpdateService.shared)
            .environmentObject(privacyMode)
            .environmentObject(sidebarManager)
            .environmentObject(toolbarManager)
            .environmentObject(dialogManager)
            .environmentObject(toastManager)
            .dialogs(manager: dialogManager)
            .modelContext(tabContext)
            .modelContext(historyContext)
            .modelContext(downloadContext)
            .withTheme()
            // Private windows are always dark, like Safari's. Through SwiftUI:
            // it manages the window's appearance and reset one set directly.
            .preferredColorScheme(privacyMode.isPrivate ? .dark : nil)
            .enableInjection()
            // External links: reuse this window instead of opening a new one
            // per link. `onOpenURL` only runs once the view is ready, so links
            // that launch Ora are not lost. Private windows never take them.
            .handlesExternalEvents(
                preferring: privacyMode.isPrivate ? [] : ["*"],
                allowing: privacyMode.isPrivate ? [] : ["*"]
            )
            .onOpenURL { url in
                guard !privacyMode.isPrivate else { return }
                tabManager.openTab(
                    url: url,
                    historyManager: historyManager,
                    downloadManager: downloadManager,
                    focusAfterOpening: true,
                    isPrivate: false
                )
            }
            // The window's undo manager (⌘Z reopens a closed tab), and files
            // from Finder that open in this window (see `ExternalFileOpener`),
            // including those that launched Ora before it existed.
            .onChange(of: window, initial: true) { _, newWindow in
                tabManager.windowUndoManager = newWindow?.undoManager
                // Keyboard shortcuts only act on the keys typed in this window.
                keyModifierListener.window = newWindow
                // Private windows are named so in the Window menu and Mission Control.
                if privacyMode.isPrivate, let newWindow {
                    newWindow.title = "Private Browsing"
                }
                if let newWindow {
                    WebExtensionsHub.registerWindow(
                        newWindow, tabManager: tabManager, isPrivate: privacyMode.isPrivate
                    )
                }
                guard let newWindow, !privacyMode.isPrivate else { return }
                BrowsingTimeTracker.shared.register(newWindow, tabManager: tabManager)
                BrowserWindows.normal.add(newWindow)
                for file in ExternalFileOpener.shared.register(newWindow) {
                    tabManager.openTab(
                        url: file,
                        historyManager: historyManager,
                        downloadManager: downloadManager,
                        focusAfterOpening: true,
                        isPrivate: false
                    )
                }
            }
            .onAppear {
                downloadManager.toastManager = toastManager
                Task {
                    let containerIDs = await MainActor.run {
                        (try? tabContext.fetch(FetchDescriptor<TabContainer>()))?.map(\.id) ?? []
                    }
                    await AdBlockService.shared.start(containerIDs: containerIDs)
                    if !privacyMode.isPrivate {
                        await MainActor.run {
                            PrivacyDefaults.offerIfNeeded(containerIDs: containerIDs, dialogManager: dialogManager)
                        }
                    }
                }

                // Dialog keyboard shortcuts (highest priority — checked first)
                keyModifierListener.registerKeyDownHandler { event in
                    // Escape: dismiss top dialog
                    if event.keyCode == 53, !dialogManager.dialogs.isEmpty {
                        DispatchQueue.main.async { dialogManager.dismissTop() }
                        return true
                    }
                    // Return: confirm top dialog (only if it carries a confirm action)
                    if event.keyCode == 36, let onConfirm = dialogManager.dialogs.last?.onConfirm {
                        DispatchQueue.main.async {
                            onConfirm()
                            dialogManager.dismissTop()
                        }
                        return true
                    }
                    return false
                }

                keyModifierListener.registerKeyDownHandler { event in
                    guard !appState.isFloatingTabSwitchVisible else { return false }

                    if event.keyCode == 48 {
                        if event.modifierFlags.contains(.control) {
                            DispatchQueue.main.async {
                                appState.isFloatingTabSwitchVisible = true
                            }
                            return true
                        }
                    }
                    return false
                }

                // Full screen: macOS only offers Globe+F in the View menu, which
                // keyboards without a Globe key cannot type. Honour Ora's own,
                // customizable shortcut (⌃⌘F by default) as well.
                keyModifierListener.registerKeyDownHandler { event in
                    guard KeyChord(fromEvent: event) == KeyboardShortcuts.Window.fullscreen.currentChord,
                          // `KeyModifierListener` only passes the events of this window.
                          let targetWindow = event.window
                    else { return false }
                    targetWindow.toggleFullScreen(nil)
                    return true
                }

                // Cmd+Q quit confirmation
                NotificationCenter.default.addObserver(forName: .quitRequested, object: nil, queue: .main) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    guard window != nil else {
                        NSApp.reply(toApplicationShouldTerminate: true)
                        return
                    }
                    dialogManager.confirm(
                        title: "Quit Ora?",
                        message: "Are you sure you want to quit?",
                        iconImage: Image("OraColorLogo"),
                        confirmLabel: "Quit",
                        variant: .destructive,
                        onConfirm: { NSApp.reply(toApplicationShouldTerminate: true) },
                        onCancel: { NSApp.reply(toApplicationShouldTerminate: false) }
                    )
                }

                NotificationCenter.default.addObserver(forName: .showLauncher, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        if tabManager.activeTab != nil {
                            appState.showLauncher.toggle()
                        }
                    }
                }
                // History panel; private windows keep no history.
                NotificationCenter.default.addObserver(forName: .showHistory, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow,
                              !privacyMode.isPrivate
                        else { return }
                        appState.showLauncher = false
                        appState.showNotes = false
                        appState.showTime = false
                        appState.showHistory.toggle()
                    }
                }
                // Notes of the space; private windows keep no notes.
                NotificationCenter.default.addObserver(forName: .showNotes, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow,
                              !privacyMode.isPrivate
                        else { return }
                        appState.showLauncher = false
                        appState.showHistory = false
                        appState.showTime = false
                        appState.showNotes.toggle()
                    }
                }
                NotificationCenter.default.addObserver(forName: .showImport, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window, !privacyMode.isPrivate else { return }
                        appState.showImport = true
                    }
                }
                NotificationCenter.default.addObserver(forName: .deleteSpace, object: nil, queue: .main) { note in
                    guard let spaceID = note.userInfo?["spaceID"] as? UUID else { return }
                    Task { @MainActor in
                        let descriptor = FetchDescriptor<TabContainer>(predicate: #Predicate { $0.id == spaceID })
                        guard note.object as? NSWindow === window,
                              let container = try? tabManager.modelContext.fetch(descriptor).first
                        else { return }
                        tabManager.deleteContainer(container)
                    }
                }
                NotificationCenter.default.addObserver(forName: .showSettings, object: nil, queue: .main) { note in
                    let opens = note.userInfo?["open"] as? Bool == true
                    Task { @MainActor in
                        guard note.object as? NSWindow === window else { return }
                        if opens { appState.showSettings = true } else { appState.showSettings.toggle() }
                    }
                }
                NotificationCenter.default.addObserver(forName: .showTime, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow, !privacyMode.isPrivate
                        else { return }
                        appState.showLauncher = false
                        appState.showHistory = false
                        appState.showNotes = false
                        appState.showTime.toggle()
                    }
                }
                NotificationCenter.default.addObserver(forName: .showTasks, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow, !privacyMode.isPrivate,
                              tabManager.activeTab != nil
                        else { return }
                        appState.showTasks.toggle()
                    }
                }
                // A task reminder clicked: its space and its list, in the front window.
                NotificationCenter.default.addObserver(forName: .openTaskReminder, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard window === NSApp.keyWindow, !privacyMode.isPrivate else { return }
                        tabManager.showTasks(ofSpace: note.userInfo?["spaceID"] as? UUID)
                        appState.showTasks = tabManager.activeTab != nil
                    }
                }
                NotificationCenter.default.addObserver(forName: .openPeekInTab, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.openPeekInTab()
                    }
                }
                // New Split View: the tab opened from the launcher goes at the
                // right of the current one.
                NotificationCenter.default.addObserver(forName: .newSplitView, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow,
                              tabManager.prepareNewSplit()
                        else { return }
                        appState.showHistory = false
                        appState.showLauncher = true
                    }
                }
                NotificationCenter.default.addObserver(forName: .closeActiveTab, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.closeActiveTab()
                    }
                }
                NotificationCenter.default.addObserver(forName: .restoreLastTab, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.restoreLastTab()
                    }
                }
                NotificationCenter.default.addObserver(forName: .findInPage, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        if let activeTab = tabManager.activeTab { appState.showFinderIn = activeTab.id }
                    }
                }
                NotificationCenter.default.addObserver(forName: .toggleFullURL, object: nil, queue: .main) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    toolbarManager.showFullURL.toggle()
                }
                NotificationCenter.default.addObserver(forName: .toggleToolbar, object: nil, queue: .main) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toolbarManager.isToolbarHidden.toggle()
                    }
                }
                NotificationCenter.default.addObserver(forName: .reloadPage, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.activeTab?.reload()
                    }
                }
                #if DEBUG
                    NotificationCenter.default.addObserver(
                        forName: .simulatePageCrash,
                        object: nil,
                        queue: .main
                    ) { note in
                        Task { @MainActor in
                            guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                            // The sandbox forbids Ora to kill a web content process
                            // itself: copy the command that crashes them, to run in
                            // Terminal (SIGKILL ends a process exactly like a crash).
                            let tabs = tabManager.activeContainer?.tabs ?? []
                            let pids = Set(tabs.compactMap { $0.browserPage?.webContentProcessIdentifier })
                            guard !pids.isEmpty else {
                                print("[Simulate crash] No web content process found")
                                return
                            }
                            let command = "kill -9 " + pids.sorted().map(String.init).joined(separator: " ")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                            print("[Simulate crash] Copied to the clipboard, run it in Terminal: \(command)")
                        }
                    }
                #endif
                NotificationCenter.default.addObserver(forName: .goBack, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.activeTab?.goBack()
                    }
                }
                NotificationCenter.default.addObserver(forName: .goForward, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        tabManager.activeTab?.goForward()
                    }
                }
                NotificationCenter.default.addObserver(forName: .togglePinTab, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        if let tab = tabManager.activeTab { tabManager.togglePinTab(tab) }
                    }
                }
                NotificationCenter.default.addObserver(forName: .nextTab, object: nil, queue: .main) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    appState.isFloatingTabSwitchVisible = true
                }
                NotificationCenter.default.addObserver(forName: .previousTab, object: nil, queue: .main) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    appState.isFloatingTabSwitchVisible = true
                }
                NotificationCenter.default.addObserver(forName: .setAppearance, object: nil, queue: .main) { note in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    if let raw = note.userInfo?["appearance"] as? String,
                       let mode = AppAppearance(rawValue: raw)
                    {
                        AppearanceManager.shared.appearance = mode
                    }
                }
                NotificationCenter.default.addObserver(forName: .selectTabAtIndex, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                        if let index = note.userInfo?["index"] as? Int {
                            tabManager.selectTabAtIndex(index)
                        }
                    }
                }
                NotificationCenter.default.addObserver(forName: .openURL, object: nil, queue: .main) { note in
                    Task { @MainActor in
                        let targetWindow = window ?? NSApp.keyWindow
                        if let sender = note.object as? NSWindow {
                            guard sender === targetWindow else { return }
                        } else {
                            guard NSApp.keyWindow === targetWindow else { return }
                        }
                        guard let url = note.userInfo?["url"] as? URL else { return }
                        tabManager.openTab(
                            url: url,
                            historyManager: historyManager,
                            downloadManager: downloadManager,
                            focusAfterOpening: true,
                            isPrivate: privacyMode.isPrivate
                        )
                    }
                }

                NotificationCenter.default
                    .addObserver(forName: .spacePrivacySettingsChanged, object: nil, queue: .main) { note in
                        Task { @MainActor in
                            guard let containerId = note.userInfo?["containerId"] as? UUID else { return }
                            tabManager.refreshPrivacySettings(for: containerId)
                        }
                    }

                // Clear cache and reload
                NotificationCenter.default
                    .addObserver(forName: .clearCacheAndReload, object: nil, queue: .main) { note in
                        Task { @MainActor in
                            guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                            if let activeTab = tabManager.activeTab {
                                let host = activeTab.url.host ?? ""
                                let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                                PrivacyService
                                    .clearCacheForHost(
                                        for: domain,
                                        container: activeTab.container
                                    ) { [weak toastManager] in
                                        DispatchQueue.main.async {
                                            activeTab.reload()
                                            toastManager?.show("Cache cleared for \(domain)", icon: .system("trash"))
                                        }
                                    }
                            }
                        }
                    }

                // Clear cookies and reload
                NotificationCenter.default
                    .addObserver(forName: .clearCookiesAndReload, object: nil, queue: .main) { note in
                        Task { @MainActor in
                            guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }

                            if let activeTab = tabManager.activeTab {
                                let host = activeTab.url.host ?? ""
                                let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                                PrivacyService
                                    .clearCookiesForHost(
                                        for: host,
                                        container: activeTab.container
                                    ) { [weak toastManager] in
                                        DispatchQueue.main.async {
                                            activeTab.reload()
                                            toastManager?.show("Cookies cleared for \(domain)", icon: .system("trash"))
                                        }
                                    }
                            }
                        }
                    }
            }
    }
}
