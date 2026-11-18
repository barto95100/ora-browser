import AppKit

/// What becomes of a browser window Little Ombre hid when the last Little
/// Ombre holding it closes.
enum HiddenBrowserWindow: Equatable {
    /// Made for the link while Ombre had no window: closed, as before the link.
    case close
    /// Opened as Ombre launched (the link launched it, its windows came
    /// back): shown, as a launch would.
    case show
}

/// A link from another app while no browser window is open: SwiftUI makes
/// one to hand it over (a link is always given to a window). Little Ombre
/// then opens alone, like Little Arc: that window is hidden while a Little
/// Ombre uses it, shown by "Open in Ombre", and closed (or shown, at launch)
/// once none uses it.
extension LittleOmbreWindow {
    /// A window that appeared less than this before its link was made for it.
    static let windowForLinkDelay: Duration = .seconds(1)
    /// Ombre launched less than this before: the link launched it.
    static let launchDelay: TimeInterval = 5

    static var secondsSinceLaunch: TimeInterval {
        -(NSRunningApplication.current.launchDate ?? .distantPast).timeIntervalSinceNow
    }

    /// Ombre launched less than `launchDelay` ago.
    static var launchedRecently: Bool {
        secondsSinceLaunch < launchDelay
    }

    /// What to do with `browserWindow`, which handed over a link Little Ombre
    /// opened: nothing when another browser window is open (or it was there
    /// before the link), else hide it.
    static func hiding(
        _ browserWindow: NSWindow,
        appearedFor elapsed: Duration,
        otherWindows: [NSWindow],
        launchedFor launch: TimeInterval,
        isOpen: (NSWindow) -> Bool = { $0.isVisible || $0.isMiniaturized }
    ) -> HiddenBrowserWindow? {
        let decision = hidingDecision(
            browserWindow, appearedFor: elapsed, otherWindows: otherWindows, launchedFor: launch, isOpen: isOpen
        )
        guard case let .hide(fate) = decision else { return nil }
        return fate
    }

    /// `hiding`, with why a window is kept (for the log).
    enum HidingDecision: Equatable {
        case hide(HiddenBrowserWindow)
        case keep(reason: String)
    }

    static func hidingDecision(
        _ browserWindow: NSWindow,
        appearedFor elapsed: Duration,
        otherWindows: [NSWindow],
        launchedFor launch: TimeInterval,
        isOpen: (NSWindow) -> Bool = { $0.isVisible || $0.isMiniaturized }
    ) -> HidingDecision {
        // Already hidden by another Little Ombre: kept hidden for this one too.
        if let held = held(browserWindow) { return .hide(held) }
        guard isOpen(browserWindow) else { return .keep(reason: "not on screen") } // not shown
        guard elapsed < windowForLinkDelay else {
            let since = elapsed.formatted(.units(allowed: [.seconds]))
            return .keep(reason: "there before the link (\(since))") // not shown
        }
        let others = otherWindows.count(where: { $0 !== browserWindow && isOpen($0) })
        guard others == 0 else { return .keep(reason: "\(others) other browser window(s) open") } // not shown
        return .hide(launch < launchDelay ? .show : .close)
    }

    /// How long a window handed over before it shows is waited for (longer
    /// while Ombre launches: restoring its windows takes a while).
    static var onScreenWait: Duration {
        launchedRecently ? .seconds(launchDelay) : .seconds(2)
    }

    /// Browser windows shown for a tab of Little Ombre: the user's now,
    /// never hidden by a decision that was waiting for them.
    static let shownForATab = NSHashTable<NSWindow>.weakObjects()

    /// Runs `action` once `window` is on screen: SwiftUI may hand a window
    /// over before ordering it in (at launch, a link can come first).
    /// `expired` instead if it isn't within `limit` (or closes before): a
    /// window shown later is the user's, never hidden.
    static func whenOnScreen(
        _ window: NSWindow,
        within limit: Duration = onScreenWait,
        _ action: @escaping @MainActor () -> Void,
        expired: @escaping @MainActor () -> Void = {}
    ) {
        if isOpen(window) {
            action()
            return
        }
        let wait = OnScreenWait(action: action, expired: expired)
        let center = NotificationCenter.default
        // Ordered in: its occlusion changes; a launch window also becomes key.
        let names = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification
        ]
        for name in names {
            wait.observers.append(center.addObserver(forName: name, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    guard isOpen(window), wait.end() else { return }
                    wait.action()
                }
            })
        }
        wait.observers.append(center.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { if wait.end() { wait.expired() } }
        })
        Task { @MainActor in
            try? await Task.sleep(for: limit)
            if wait.end() { wait.expired() }
        }
    }

    /// Its browser window, known now or once SwiftUI gives it (a link
    /// handed over before): one a Little Ombre holds hidden is held by this
    /// one too, or it would close under it.
    func attach(to browserWindow: NSWindow?) {
        self.browserWindow = browserWindow
        if let browserWindow, let held = Self.held(browserWindow) { hiddenBrowserWindow = held }
    }

    /// Hides the browser window it came from, until "Open in Ombre" or its close.
    func hideBrowserWindow(_ fate: HiddenBrowserWindow) {
        guard let browserWindow else { return }
        hiddenBrowserWindow = fate
        browserWindow.isExcludedFromWindowsMenu = true
        browserWindow.orderOut(nil)
    }

    /// Its page went to a tab: the browser window shows, for every Little
    /// Ombre that hid it.
    func showBrowserWindow() {
        guard let browserWindow else { return }
        Self.shownForATab.add(browserWindow)
        for little in Self.openWindows where little.browserWindow === browserWindow {
            little.hiddenBrowserWindow = nil
        }
        hiddenBrowserWindow = nil
        Self.reveal(browserWindow)
    }

    /// A tab opened in the background: the browser window shows behind
    /// Little Ombre (one it hid is kept, and no longer closed with it).
    func showBrowserWindowBehind() {
        guard let browserWindow else { return }
        Self.shownForATab.add(browserWindow)
        for little in Self.openWindows where little.browserWindow === browserWindow {
            little.hiddenBrowserWindow = nil
        }
        hiddenBrowserWindow = nil
        browserWindow.isExcludedFromWindowsMenu = false
        if TestHost.isActive {
            browserWindow.orderBack(nil)
        } else if !Self.isOpen(browserWindow) {
            browserWindow.order(.below, relativeTo: window.windowNumber)
        }
    }

    /// `browserWindow` is needed (a link opens in it as a tab): shown if a
    /// Little Ombre hid it.
    static func browserWindowNeeded(_ browserWindow: NSWindow) {
        shownForATab.add(browserWindow)
        guard held(browserWindow) != nil else { return }
        for little in openWindows where little.browserWindow === browserWindow {
            little.hiddenBrowserWindow = nil
        }
        reveal(browserWindow)
    }

    /// Closed: the browser window it hid goes, once no Little Ombre uses it.
    func releaseHiddenBrowserWindow() {
        guard let fate = hiddenBrowserWindow, let browserWindow else { return }
        hiddenBrowserWindow = nil
        guard Self.held(browserWindow) == nil else { return }
        // Shown meanwhile (settings, an extension): it stays, in the Window menu.
        guard !Self.isOpen(browserWindow) else {
            browserWindow.isExcludedFromWindowsMenu = false
            return
        }
        switch fate {
        case .close:
            // Once Little Ombre is gone (the window closes the Little Ombres
            // it has), unless a link meanwhile opened one from it.
            DispatchQueue.main.async {
                guard Self.held(browserWindow) == nil, !Self.isOpen(browserWindow) else { return }
                browserWindow.close()
            }
        case .show:
            Self.reveal(browserWindow)
        }
    }

    /// How another Little Ombre holds `browserWindow` hidden, if one does.
    static func held(_ browserWindow: NSWindow) -> HiddenBrowserWindow? {
        openWindows.lazy.filter { $0.browserWindow === browserWindow }.compactMap(\.hiddenBrowserWindow).first
    }

    static func isOpen(_ window: NSWindow) -> Bool {
        window.isVisible || window.isMiniaturized
    }

    private static func reveal(_ browserWindow: NSWindow) {
        browserWindow.isExcludedFromWindowsMenu = false
        if TestHost.isActive {
            browserWindow.orderBack(nil)
        } else {
            browserWindow.makeKeyAndOrderFront(nil)
        }
    }
}

/// The observers of a window `whenOnScreen` waits for, removed once done.
@MainActor
private final class OnScreenWait {
    let action: @MainActor () -> Void
    let expired: @MainActor () -> Void
    var observers: [NSObjectProtocol] = []
    private var isOver = false

    init(action: @escaping @MainActor () -> Void, expired: @escaping @MainActor () -> Void) {
        self.action = action
        self.expired = expired
    }

    /// Ends the wait: true the first time only.
    func end() -> Bool {
        guard !isOver else { return false }
        isOver = true
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        return true
    }
}
