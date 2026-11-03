import SwiftData
import SwiftUI

/// What a browser window's menu commands act on: its window and its managers.
///
/// The commands arrive as notifications (see `OmbreCommands`). Each window
/// subscribes with `onReceive`, so its subscriptions end with the window: a
/// closed window no longer reacts, and no longer keeps its managers alive.
struct WindowCommandTargets {
    let window: NSWindow?
    let appState: AppState
    let tabManager: TabManager
    let historyManager: HistoryManager
    let downloadManager: DownloadManager
    let privacyMode: PrivacyMode
    let toolbarManager: ToolbarManager
    let dialogManager: DialogManager
    let toastManager: ToastManager
}

extension View {
    /// The menu commands of a browser window, for as long as it is shown.
    func windowCommands(_ targets: WindowCommandTargets) -> some View {
        modifier(WindowAppCommands(targets: targets))
            .modifier(WindowTabCommands(targets: targets))
            .modifier(WindowPageCommands(targets: targets))
    }

    /// Runs `action` for each `name` notification while the view is shown.
    /// They are all posted on the main thread, so it runs right away, as
    /// with an observer on the main queue.
    func onNotification(_ name: Notification.Name, perform action: @escaping (Notification) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: name), perform: action)
    }
}

/// Quit, panels, settings and appearance.
private struct WindowAppCommands: ViewModifier {
    let targets: WindowCommandTargets

    func body(content: Content) -> some View {
        let window = targets.window
        let appState = targets.appState
        let tabManager = targets.tabManager
        let privacyMode = targets.privacyMode
        let dialogManager = targets.dialogManager

        content
            // Cmd+Q quit confirmation
            .onNotification(.quitRequested) { note in
                guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                guard window != nil else {
                    NSApp.reply(toApplicationShouldTerminate: true)
                    return
                }
                dialogManager.confirm(
                    title: "Quit Ombre?",
                    message: "Are you sure you want to quit?",
                    iconImage: Image(nsImage: NSApp.applicationIconImage),
                    confirmLabel: "Quit",
                    variant: .destructive,
                    onConfirm: { NSApp.reply(toApplicationShouldTerminate: true) },
                    onCancel: { NSApp.reply(toApplicationShouldTerminate: false) }
                )
            }
            .onNotification(.showLauncher) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    if tabManager.activeTab != nil {
                        appState.showLauncher.toggle()
                    }
                }
            }
            // History panel; private windows keep no history.
            .onNotification(.showHistory) { note in
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
            .onNotification(.showNotes) { note in
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
            .onNotification(.showImport) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window, !privacyMode.isPrivate else { return }
                    appState.showImport = true
                }
            }
            .onNotification(.showSettings) { note in
                let opens = note.userInfo?["open"] as? Bool == true
                Task { @MainActor in
                    guard note.object as? NSWindow === window else { return }
                    if opens { appState.showSettings = true } else { appState.showSettings.toggle() }
                }
            }
            .onNotification(.showTime) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow, !privacyMode.isPrivate
                    else { return }
                    appState.showLauncher = false
                    appState.showHistory = false
                    appState.showNotes = false
                    appState.showTime.toggle()
                }
            }
            .onNotification(.showTasks) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow, !privacyMode.isPrivate,
                          tabManager.activeTab != nil
                    else { return }
                    appState.showTasks.toggle()
                }
            }
            // A task reminder clicked: its space and its list, in the front window.
            .onNotification(.openTaskReminder) { note in
                Task { @MainActor in
                    guard window === NSApp.keyWindow, !privacyMode.isPrivate else { return }
                    tabManager.showTasks(ofSpace: note.userInfo?["spaceID"] as? UUID)
                    appState.showTasks = tabManager.activeTab != nil
                }
            }
            .onNotification(.setAppearance) { note in
                guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                if let raw = note.userInfo?["appearance"] as? String,
                   let mode = AppAppearance(rawValue: raw)
                {
                    AppearanceManager.shared.appearance = mode
                }
            }
    }
}

/// Spaces, tabs and navigation.
private struct WindowTabCommands: ViewModifier {
    let targets: WindowCommandTargets

    func body(content: Content) -> some View {
        let window = targets.window
        let appState = targets.appState
        let tabManager = targets.tabManager

        content
            .onNotification(.deleteSpace) { note in
                guard let spaceID = note.userInfo?["spaceID"] as? UUID else { return }
                Task { @MainActor in
                    let descriptor = FetchDescriptor<TabContainer>(predicate: #Predicate { $0.id == spaceID })
                    guard note.object as? NSWindow === window,
                          let container = try? tabManager.modelContext.fetch(descriptor).first
                    else { return }
                    tabManager.deleteContainer(container)
                }
            }
            .onNotification(.openPeekInTab) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    tabManager.openPeekInTab()
                }
            }
            // New Split View: the tab opened from the launcher goes at the
            // right of the current one.
            .onNotification(.newSplitView) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow,
                          tabManager.prepareNewSplit()
                    else { return }
                    appState.showHistory = false
                    appState.showLauncher = true
                }
            }
            .onNotification(.closeActiveTab) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    tabManager.closeActiveTab()
                }
            }
            .onNotification(.restoreLastTab) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    tabManager.restoreLastTab()
                }
            }
            .onNotification(.goBack) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    tabManager.activeTab?.goBack()
                }
            }
            .onNotification(.goForward) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    tabManager.activeTab?.goForward()
                }
            }
            .onNotification(.togglePinTab) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    if let tab = tabManager.activeTab { tabManager.togglePinTab(tab) }
                }
            }
            .onNotification(.nextTab) { note in
                guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                appState.isFloatingTabSwitchVisible = true
            }
            .onNotification(.previousTab) { note in
                guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                appState.isFloatingTabSwitchVisible = true
            }
            .onNotification(.selectTabAtIndex) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    if let index = note.userInfo?["index"] as? Int {
                        tabManager.selectTabAtIndex(index)
                    }
                }
            }
            .onNotification(.openURL) { note in
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
                        historyManager: targets.historyManager,
                        downloadManager: targets.downloadManager,
                        focusAfterOpening: true,
                        isPrivate: targets.privacyMode.isPrivate
                    )
                }
            }
    }
}

/// The page in front: find, reload, toolbar and website data.
private struct WindowPageCommands: ViewModifier {
    let targets: WindowCommandTargets

    func body(content: Content) -> some View {
        let window = targets.window
        let appState = targets.appState
        let tabManager = targets.tabManager
        let toolbarManager = targets.toolbarManager

        content
            .onNotification(.findInPage) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    if let activeTab = tabManager.activeTab { appState.showFinderIn = activeTab.id }
                }
            }
            .onNotification(.toggleFullURL) { note in
                guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                toolbarManager.showFullURL.toggle()
            }
            .onNotification(.toggleToolbar) { note in
                guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    toolbarManager.isToolbarHidden.toggle()
                }
            }
            .onNotification(.reloadPage) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    tabManager.activeTab?.reload()
                }
            }
        #if DEBUG
            .onNotification(.simulatePageCrash) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    // The sandbox forbids Ombre to kill a web content process
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
            // Every open window showing the space reloads its pages; a closed
            // window has stopped listening.
            .onNotification(.spacePrivacySettingsChanged) { note in
                Task { @MainActor in
                    guard let containerId = note.userInfo?["containerId"] as? UUID else { return }
                    tabManager.refreshPrivacySettings(for: containerId)
                }
            }
            // Clear cache and reload
            .onNotification(.clearCacheAndReload) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    reloadClearing(.cache, tabManager: tabManager)
                }
            }
            // Clear cookies and reload
            .onNotification(.clearCookiesAndReload) { note in
                Task { @MainActor in
                    guard note.object as? NSWindow === window ?? NSApp.keyWindow else { return }
                    reloadClearing(.cookies, tabManager: tabManager)
                }
            }
    }

    private enum WebsiteData { case cache, cookies }

    /// Clears the active page's cache or cookies, then reloads it.
    @MainActor
    private func reloadClearing(_ data: WebsiteData, tabManager: TabManager) {
        guard let activeTab = tabManager.activeTab else { return }
        let host = activeTab.url.host ?? ""
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let toastManager = targets.toastManager
        switch data {
        case .cache:
            PrivacyService.clearCacheForHost(for: domain, container: activeTab.container) { [weak toastManager] in
                DispatchQueue.main.async {
                    activeTab.reload()
                    toastManager?.show("Cache cleared for \(domain)", icon: .system("trash"))
                }
            }
        case .cookies:
            PrivacyService.clearCookiesForHost(for: host, container: activeTab.container) { [weak toastManager] in
                DispatchQueue.main.async {
                    activeTab.reload()
                    toastManager?.show("Cookies cleared for \(domain)", icon: .system("trash"))
                }
            }
        }
    }
}

extension View {
    /// What a browser window does when it closes, and when the app quits.
    func windowLifecycle(window: NSWindow?, tabManager: TabManager) -> some View {
        modifier(WindowLifecycle(window: window, tabManager: tabManager))
    }
}

/// A closing window stops its pages and timers, closes the popups its pages
/// opened and saves; quitting saves too.
private struct WindowLifecycle: ViewModifier {
    let window: NSWindow?
    let tabManager: TabManager

    func body(content: Content) -> some View {
        content
            .onNotification(NSWindow.willCloseNotification) { note in
                // Only this window's own closing (not a sheet or a popup).
                guard let window, note.object as? NSWindow === window else { return }
                MainActor.assumeIsolated {
                    BrowserPopupWindow.closePopups(openedFrom: window)
                    tabManager.tearDown()
                }
            }
            .onNotification(NSApplication.willTerminateNotification) { _ in
                MainActor.assumeIsolated {
                    tabManager.saveOnQuit()
                }
            }
    }
}
