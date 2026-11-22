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

/// A browser window: its session (database context and managers) is made
/// once, when SwiftUI first creates the window's state; `init` itself does
/// nothing else.
struct OmbreRoot: View {
    @StateObject private var session: WindowSession

    init(isPrivate: Bool = false) {
        _session = StateObject(wrappedValue: WindowSession(isPrivate: isPrivate))
    }

    var body: some View {
        BrowserWindowRoot(session: session)
    }
}

/// A browser window's content, with its session's managers.
private struct BrowserWindowRoot: View {
    @StateObject private var appState = AppState()
    @StateObject private var keyModifierListener = KeyModifierListener()
    @ObservedObject private var mediaController: MediaController
    @ObservedObject private var tabManager: TabManager
    @ObservedObject private var historyManager: HistoryManager
    @ObservedObject private var downloadManager: DownloadManager
    @ObservedObject private var privacyMode: PrivacyMode
    @StateObject private var sidebarManager = SidebarManager()
    @StateObject private var toolbarManager = ToolbarManager()
    @StateObject private var dialogManager = DialogManager()
    private let toastManager = ToastManager.shared

    @ObserveInjection var inject

    private let modelContext: ModelContext
    @State private var window: NSWindow?
    /// When the window appeared: a link right after made it (see `LittleOmbreWindow.hiding`).
    @State private var windowAppearance: ContinuousClock.Instant?
    /// A Little Ombre opened for a link before the window was known.
    @State private var littleAwaitingWindow: LittleOmbreWindow?

    init(session: WindowSession) {
        modelContext = session.modelContext
        mediaController = session.mediaController
        tabManager = session.tabManager
        historyManager = session.historyManager
        downloadManager = session.downloadManager
        privacyMode = session.privacyMode
    }

    var body: some View {
        BrowserView()
            .sheet(item: $appState.importSource) { source in
                switch source {
                case .zen, .arc: BrowserImportSheet(source: source)
                case .safari: SafariImportSheet()
                }
            }
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
            // "Open Peek in New Tab" is only on while Peek shows.
            .focusedSceneValue(\.isPeekOpen, tabManager.peek != nil)
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
            .modelContext(modelContext)
            .withTheme()
            // Private windows are always dark, like Safari's. Through SwiftUI:
            // it manages the window's appearance and reset one set directly.
            .preferredColorScheme(privacyMode.isPrivate ? .dark : nil)
            .enableInjection()
            // External links: reuse this window instead of opening a new one
            // per link. `onOpenURL` only runs once the view is ready, so links
            // that launch Ombre are not lost. Private windows never take them.
            .handlesExternalEvents(
                preferring: privacyMode.isPrivate ? [] : ["*"],
                allowing: privacyMode.isPrivate ? [] : ["*"]
            )
            .onOpenURL { url in
                let site = PageLog.site(url, isPrivate: privacyMode.isPrivate)
                let when = LittleOmbreWindow.launchedRecently ? "at launch" : "while running" // not shown
                let since = LinkLog.sinceLaunch(LittleOmbreWindow.secondsSinceLaunch)
                let known = window == nil ? "not yet known" : "known" // not shown
                LinkLog.notice("link received (\(site)) \(when), \(since); window \(known)") // not shown
                guard !privacyMode.isPrivate else {
                    LinkLog.notice("link ignored: private window") // not shown
                    return
                }
                // An address rule's space, else the active one.
                let ruleSpace = tabManager.addressRuleSpace(for: url, from: tabManager.activeContainer)
                // Like Arc: in a small window of its own, unless turned off.
                let inLittleOmbre = SettingsStore.shared.opensLinksInLittleOmbre
                if inLittleOmbre,
                   let little = LittleOmbreWindow.open(url, from: tabManager, window: window, in: ruleSpace)
                {
                    LinkLog.notice("link opened in Little Ombre") // not shown
                    little.keepInFrontAfterLink()
                    if let window, let appeared = windowAppearance {
                        hideIfMadeForTheLink(window, by: little, appearedFor: .now - appeared)
                    } else {
                        littleAwaitingWindow = little
                    }
                    return
                }
                let why = inLittleOmbre ? "Little Ombre couldn't open (no space)" : "Little Ombre off" // not shown
                LinkLog.notice("link opened in a tab: \(why)") // not shown
                // In a tab: the window shows, even one a Little Ombre hid.
                if let window { LittleOmbreWindow.browserWindowNeeded(window) }
                if tabManager.openTab(
                    url: url,
                    historyManager: historyManager,
                    downloadManager: downloadManager,
                    focusAfterOpening: true,
                    isPrivate: false,
                    in: ruleSpace
                ) == nil {
                    LinkLog.notice("link lost: no tab could open (no space)") // not shown
                }
            }
            // The window's undo manager (⌘Z reopens a closed tab), and files
            // from Finder that open in this window (see `ExternalFileOpener`),
            // including those that launched Ombre before it existed.
            .onChange(of: window, initial: true) { _, newWindow in
                tabManager.windowUndoManager = newWindow?.undoManager
                // Keyboard shortcuts only act on the keys typed in this window.
                keyModifierListener.window = newWindow
                // Private windows are named so in the Window menu and Mission Control.
                if privacyMode.isPrivate, let newWindow {
                    newWindow.title = String(localized: "Private Browsing")
                }
                if let newWindow {
                    windowAppearance = .now
                    if let little = littleAwaitingWindow {
                        littleAwaitingWindow = nil
                        little.attach(to: newWindow)
                        hideIfMadeForTheLink(newWindow, by: little, appearedFor: .zero)
                    }
                    // Counted when asking to quit, normal or private.
                    BrowserWindows.browsing.add(newWindow)
                    BrowserWindows.allTabManagers.setObject(tabManager, forKey: newWindow)
                    WebExtensionsHub.registerWindow(
                        newWindow, tabManager: tabManager, isPrivate: privacyMode.isPrivate
                    )
                }
                guard let newWindow, !privacyMode.isPrivate else { return }
                // The database couldn't be opened: say so, once.
                if let notice = DatabaseRecovery.takePendingNotice() {
                    DatabaseRecovery.presentNotice(notice, in: newWindow)
                }
                BrowsingTimeTracker.shared.register(newWindow, tabManager: tabManager)
                BrowserWindows.normal.add(newWindow)
                BrowserWindows.tabManagers.setObject(tabManager, forKey: newWindow)
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
            // Closing the window stops and frees its pages; quitting saves.
            .windowLifecycle(window: window, tabManager: tabManager, isPrivate: privacyMode.isPrivate)
            // The menu commands: they stop with the window (see `windowCommands`).
            .windowCommands(
                WindowCommandTargets(
                    window: window,
                    appState: appState,
                    tabManager: tabManager,
                    historyManager: historyManager,
                    downloadManager: downloadManager,
                    privacyMode: privacyMode,
                    toolbarManager: toolbarManager,
                    dialogManager: dialogManager,
                    toastManager: toastManager
                )
            )
            .onAppear {
                downloadManager.toastManager = toastManager
                // The first-launch assistant's choices, before the spaces are read below.
                if !privacyMode.isPrivate, let onboarding = OnboardingHandoff.take() {
                    OnboardingApplier.apply(onboarding, tabManager: tabManager)
                }
                Task {
                    let containerIDs = await MainActor.run {
                        (try? modelContext.fetch(FetchDescriptor<TabContainer>()))?.map(\.id) ?? []
                    }
                    await AdBlockService.shared.start(containerIDs: containerIDs)
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

                    // Next and Previous Tab (⌃Tab, ⌃⇧Tab by default, customizable):
                    // here, before the menu, which text fields would take them from.
                    let chord = KeyChord(fromEvent: event)
                    let backward = chord == KeyboardShortcuts.Tabs.previous.currentChord
                    guard backward || chord == KeyboardShortcuts.Tabs.next.currentChord else { return false }
                    DispatchQueue.main.async {
                        appState.isFloatingTabSwitchBackward = backward
                        appState.isFloatingTabSwitchVisible = true
                    }
                    return true
                }

                // Full screen: macOS only offers Globe+F in the View menu, which
                // keyboards without a Globe key cannot type. Honour Ombre's own,
                // customizable shortcut (⌃⌘F by default) as well.
                keyModifierListener.registerKeyDownHandler { event in
                    guard KeyChord(fromEvent: event) == KeyboardShortcuts.Window.fullscreen.currentChord,
                          // `KeyModifierListener` only passes the events of this window.
                          let targetWindow = event.window
                    else { return false }
                    targetWindow.toggleFullScreen(nil)
                    return true
                }

                // Zoom In is ⌘+, which needs ⇧ on most keyboards: ⌘= zooms in
                // too, like Safari, while the shortcut is the default one.
                keyModifierListener.registerKeyDownHandler { event in
                    let zoomIn = KeyboardShortcuts.Zoom.zoomIn
                    guard zoomIn.currentChord.isSameKeys(as: zoomIn.defaultChord),
                          let chord = KeyChord(fromEvent: event),
                          chord.isSameKeys(as: KeyChord(keyEquivalent: .init("="), modifiers: [.command])),
                          let targetWindow = event.window
                    else { return false }
                    NotificationCenter.default.post(name: .zoomPage, object: targetWindow, userInfo: ["step": 1])
                    return true
                }
            }
    }
}

extension BrowserWindowRoot {
    /// Made only to hand over the link Little Ombre opened: hidden, Little
    /// Ombre opens alone (see `LittleOmbreWindow.hiding`). Decided once the
    /// window is on screen: at launch, SwiftUI may give it before showing
    /// it, and a window hidden then would come in front of Little Ombre.
    private func hideIfMadeForTheLink(_ window: NSWindow, by little: LittleOmbreWindow, appearedFor elapsed: Duration) {
        // Hidden by another Little Ombre: held by this one too (`attach`), at once.
        if let held = LittleOmbreWindow.held(window) {
            little.hideBrowserWindow(held)
            LinkLog.notice("browser window already hidden by another Little Ombre") // not shown
            return
        }
        if !LittleOmbreWindow.isOpen(window) {
            LinkLog.notice("browser window not on screen yet: decided once it shows") // not shown
        }
        LittleOmbreWindow.whenOnScreen(window) {
            guard LittleOmbreWindow.isLittleOmbreWindow(little.window) else {
                LinkLog.notice("browser window kept: Little Ombre already closed") // not shown
                return
            }
            guard !LittleOmbreWindow.shownForATab.contains(window) else {
                LinkLog.notice("browser window kept: shown for a tab meanwhile") // not shown
                return
            }
            let decision = LittleOmbreWindow.hidingDecision(
                window,
                appearedFor: elapsed,
                otherWindows: BrowserWindows.normal.allObjects,
                launchedFor: LittleOmbreWindow.secondsSinceLaunch
            )
            switch decision {
            case let .hide(fate):
                let then = fate == .show ? "shown" : "closed" // not shown
                LinkLog.notice("browser window hidden; \(then) with Little Ombre") // not shown
                little.hideBrowserWindow(fate)
            case let .keep(reason):
                LinkLog.notice("browser window kept: \(reason)") // not shown
            }
        } expired: {
            LinkLog.notice("browser window kept: not on screen within the wait") // not shown
        }
    }
}
