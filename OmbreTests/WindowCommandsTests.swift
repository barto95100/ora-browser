import AppKit
import Combine
@testable import Ombre
import SwiftData
import SwiftUI
import Testing

/// A browser window's menu commands (`windowCommands`) end with the window:
/// once closed, it no longer reacts and its managers are freed.
@MainActor
struct WindowCommandsTests {
    /// What a window's commands act on, held weakly to see it go.
    @MainActor
    private final class Survivors {
        weak var appState: AppState?
        weak var tabManager: TabManager?
        weak var toolbarManager: ToolbarManager?
        weak var dialogManager: DialogManager?
        var spaceIDs: [UUID] = []

        var alive: [String] {
            [
                ("AppState", appState as AnyObject?),
                ("TabManager", tabManager),
                ("ToolbarManager", toolbarManager),
                ("DialogManager", dialogManager)
            ].compactMap { $0.1 == nil ? nil : $0.0 }
        }
    }

    /// The window's content, like `OmbreRoot`: its window is known once shown.
    private struct Content: View {
        @State private var window: NSWindow?
        let targets: (NSWindow?) -> WindowCommandTargets

        var body: some View {
            Color.clear
                .background(WindowReader(window: $window))
                .windowCommands(targets(window))
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    /// Opens a window whose commands act on new managers.
    private func open(in window: NSWindow) -> Survivors {
        let survivors = Survivors()
        let managers = TabManagerTestWindow()
        let appState = AppState()
        let toolbarManager = ToolbarManager()
        let dialogManager = DialogManager()
        let privacyMode = PrivacyMode(isPrivate: false)
        survivors.appState = appState
        survivors.tabManager = managers.tabManager
        survivors.toolbarManager = toolbarManager
        survivors.dialogManager = dialogManager
        survivors.spaceIDs = managers.spaces().map(\.id)

        let content = Content { window in
            WindowCommandTargets(
                window: window,
                appState: appState,
                tabManager: managers.tabManager,
                historyManager: managers.historyManager,
                downloadManager: managers.downloadManager,
                privacyMode: privacyMode,
                toolbarManager: toolbarManager,
                dialogManager: dialogManager,
                toastManager: ToastManager.shared
            )
        }
        let host = NSHostingView(rootView: content)
        host.frame = window.contentRect(forFrameRect: window.frame)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return survivors
    }

    private func close(_ window: NSWindow) {
        window.contentView = nil
        window.close()
    }

    /// Waits up to `timeout` for `condition`, letting main-queue work run.
    private func wait(
        timeout: Duration = .seconds(2),
        until condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// Waits until the window's commands know their window (read after the
    /// first render): a `.showSettings` for it then opens its settings.
    private func waitUntilKnown(_ window: NSWindow, _ survivors: Survivors) async -> Bool {
        await wait {
            // `.showSettings` only acts on the exact window it names.
            NotificationCenter.default.post(name: .showSettings, object: window, userInfo: ["open": true])
            return survivors.appState?.showSettings == true
        }
    }

    private func cleanUp(_ survivors: Survivors) {
        for id in survivors.spaceIDs {
            SettingsStore.shared.removeContainerSettings(for: id)
        }
    }

    /// A command for the window reaches it, once its window is known (it is
    /// read after the first render, so the subscriptions see the update).
    @Test func commandForTheWindowReachesIt() async {
        let window = makeWindow()
        let survivors = open(in: window)
        defer {
            close(window)
            cleanUp(survivors)
        }

        #expect(await waitUntilKnown(window, survivors))
    }

    /// A command for another window does not reach it.
    @Test func commandForAnotherWindowDoesNotReachIt() async throws {
        let window = makeWindow()
        let survivors = open(in: window)
        defer {
            close(window)
            cleanUp(survivors)
        }
        #expect(await waitUntilKnown(window, survivors))
        let appState = try #require(survivors.appState)
        // Commands still on their way to it arrive first.
        try await Task.sleep(for: .milliseconds(100))
        appState.showSettings = false

        let other = makeWindow()
        defer { other.close() }
        NotificationCenter.default.post(name: .showSettings, object: other, userInfo: ["open": true])
        try await Task.sleep(for: .milliseconds(100))
        #expect(!appState.showSettings)
    }

    /// A closed window frees what its commands act on: nothing keeps it
    /// subscribed. With observers added on `NotificationCenter` and never
    /// removed, all of it stayed alive until the app quit.
    @Test func closedWindowFreesItsManagers() async {
        let window = makeWindow()
        let survivors = open(in: window)
        defer { cleanUp(survivors) }
        #expect(await waitUntilKnown(window, survivors))

        close(window)
        let freed = await wait { survivors.alive.isEmpty }
        #expect(freed, "Still alive: \(survivors.alive)")
    }
}

/// ⌘Q asks for confirmation in a browser window.
@MainActor
struct QuitTargetTests {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func keyBrowserWindowAsks() {
        let browser = makeWindow()
        let other = makeWindow()
        let target = BrowserWindows.quitTarget(
            keyWindow: browser, orderedWindows: [other, browser], browserWindows: [other, browser],
            isOpen: { _ in true }
        )
        #expect(target === browser)
    }

    /// From the settings or passwords window, the frontmost browser window
    /// asks; before, nothing answered and the app never quit.
    @Test func settingsWindowInFrontLetsTheFrontmostBrowserWindowAsk() {
        let settings = makeWindow()
        let back = makeWindow()
        let front = makeWindow()
        let target = BrowserWindows.quitTarget(
            keyWindow: settings, orderedWindows: [settings, front, back], browserWindows: [back, front],
            isOpen: { _ in true }
        )
        #expect(target === front)
    }

    /// A minimized browser window is not in the ordered windows, but asks.
    @Test func minimizedBrowserWindowAsks() {
        let settings = makeWindow()
        let minimized = makeWindow()
        let target = BrowserWindows.quitTarget(
            keyWindow: settings, orderedWindows: [settings], browserWindows: [minimized], isOpen: { _ in true }
        )
        #expect(target === minimized)
    }

    /// A browser window closed but not yet freed (or hidden with the app)
    /// cannot show the question: it is not chosen, or quitting would wait
    /// forever.
    @Test func closedBrowserWindowDoesNotAsk() {
        let settings = makeWindow()
        let closed = makeWindow()
        let open = makeWindow()
        let target = BrowserWindows.quitTarget(
            keyWindow: settings, orderedWindows: [settings], browserWindows: [closed, open],
            isOpen: { $0 === open }
        )
        #expect(target === open)

        let none = BrowserWindows.quitTarget(
            keyWindow: closed, orderedWindows: [closed], browserWindows: [closed], isOpen: { _ in false }
        )
        #expect(none == nil)
    }

    /// Only the settings window: nothing to ask in, the app quits.
    @Test func noBrowserWindowQuitsRightAway() {
        let settings = makeWindow()
        let target = BrowserWindows.quitTarget(
            keyWindow: settings, orderedWindows: [settings], browserWindows: []
        )
        #expect(target == nil)
    }
}

/// `KeyModifierListener` removes its event monitors with itself: a closed
/// window stops seeing the keys typed in the others.
struct KeyModifierListenerTests {
    private final class FakeMonitoring: EventMonitoring {
        private(set) var added: [NSObject] = []
        private(set) var removed: [NSObject] = []

        func addLocalMonitor(
            matching _: NSEvent.EventTypeMask,
            handler _: @escaping (NSEvent) -> NSEvent?
        ) -> Any? {
            let token = NSObject()
            added.append(token)
            return token
        }

        func removeMonitor(_ monitor: Any) {
            if let token = monitor as? NSObject { removed.append(token) }
        }
    }

    @Test func releasedListenerRemovesItsMonitors() {
        let monitoring = FakeMonitoring()
        var listener: KeyModifierListener? = KeyModifierListener(monitoring: monitoring)
        weak let released = listener
        listener?.registerKeyDownHandler { _ in false }
        #expect(monitoring.added.count == 2)
        #expect(monitoring.removed.isEmpty)

        listener = nil

        #expect(released == nil)
        #expect(monitoring.removed.count == 2)
        #expect(Set(monitoring.removed.map(ObjectIdentifier.init)) == Set(monitoring.added.map(ObjectIdentifier.init)))
    }

    /// A modifier key no longer redraws the views observing the listener
    /// (the window's root); the tab switcher hears each change once (PERF-22).
    @Test func modifierKeysAreSentNotPublished() {
        let listener = KeyModifierListener(monitoring: FakeMonitoring())
        var redraws = 0
        var changes: [NSEvent.ModifierFlags] = []
        let redrawWatch = listener.objectWillChange.sink { redraws += 1 }
        let changeWatch = listener.modifierFlagsChanged.sink { changes.append($0) }
        defer { redrawWatch.cancel()
            changeWatch.cancel()
        }

        listener.flagsChanged(to: .control)
        // The same key, with only a device bit different (left/right ⌃).
        listener.flagsChanged(to: [.control, NSEvent.ModifierFlags(rawValue: 0x1)])
        listener.flagsChanged(to: [])

        #expect(redraws == 0)
        #expect(changes == [.control, []])
        #expect(listener.modifierFlags.isEmpty)
    }
}
