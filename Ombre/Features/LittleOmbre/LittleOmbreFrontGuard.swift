import AppKit

/// A link from another app: Little Ombre opens in front with the keyboard,
/// but what follows the link can put the browser window it came from back
/// above it (SwiftUI orders the window that took the link front,
/// un-minimizing it; the app's activation raises Ombre's windows in their
/// former order, even with Little Ombre key). For a moment after the link,
/// a browser window made key, or ordered above Little Ombre, without the user
/// (no click or key typed then) gives the front back to Little Ombre, and
/// goes back to the Dock if it was minimized. Checked when a window becomes
/// key, when Little Ombre or a browser window is covered or uncovered, on
/// activation, and 0.5 s and 1 s after the link. A click, a key, "Open in
/// Ombre" or a tab opened from Little Ombre end it: the user's choice is kept.
@MainActor
final class LittleOmbreFrontGuard {
    /// How long after the link the guard watches.
    nonisolated static let duration: Duration = .seconds(2)
    /// When the order is checked again after the link, whatever happened.
    nonisolated static let checks: [Duration] = [.milliseconds(500), .seconds(1)]
    /// At most this many bring-backs per link: never a fight with something
    /// that keeps raising another window.
    nonisolated static let maximumBringBacks = 5

    /// What happened while the guard watches.
    enum Change: Equatable {
        /// A window became key: a browser window or not.
        case windowBecameKey(isBrowserWindow: Bool)
        /// Ombre became active, or the link's handling is done.
        case settled
    }

    enum Response: Equatable {
        case keep
        case bringBack
        case stop
    }

    /// What to do about `change`, `elapsed` after the link.
    nonisolated static func response(
        to change: Change,
        littleIsInFront: Bool,
        byUser: Bool,
        elapsed: Duration,
        limit: Duration = duration
    ) -> Response {
        guard elapsed < limit, !byUser else { return .stop }
        switch change {
        case let .windowBecameKey(isBrowserWindow):
            return isBrowserWindow && !littleIsInFront ? .bringBack : .keep
        case .settled:
            return littleIsInFront ? .keep : .bringBack
        }
    }

    /// The event being handled is the user's: a click or a key.
    nonisolated static func isUserEvent(_ type: NSEvent.EventType?) -> Bool {
        switch type {
        // Mouse up: a menu item chosen (the Window menu).
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown, .keyDown: true
        default: false
        }
    }

    private weak var littleWindow: NSWindow?
    private weak var browserWindow: NSWindow?
    private var wasMiniaturized: Bool
    private let start = ContinuousClock.now
    private let isBrowserWindow: @MainActor (NSWindow) -> Bool
    private let currentEventType: @MainActor () -> NSEvent.EventType?
    private let keyWindow: @MainActor () -> NSWindow?
    private let orderedWindows: @MainActor () -> [NSWindow]
    private let isActive: @MainActor () -> Bool
    private let bringBack: @MainActor () -> Void
    private var observers: [NSObjectProtocol] = []
    private var checking: Task<Void, Never>?
    private(set) var bringBacks = 0
    private(set) var isOver = false

    init(
        little littleWindow: NSWindow,
        browserWindow: NSWindow?,
        isBrowserWindow: @escaping @MainActor (NSWindow) -> Bool = { BrowserWindows.browsing.contains($0) },
        currentEventType: @escaping @MainActor () -> NSEvent.EventType? = { NSApp.currentEvent?.type },
        keyWindow: @escaping @MainActor () -> NSWindow? = { NSApp.keyWindow },
        // Those of the current Space only: a full-screen window elsewhere is
        // not above Little Ombre.
        orderedWindows: @escaping @MainActor () -> [NSWindow] = { NSApp.orderedWindows.filter(\.isOnActiveSpace) },
        isActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
        bringBack: @escaping @MainActor () -> Void
    ) {
        self.littleWindow = littleWindow
        self.browserWindow = browserWindow
        wasMiniaturized = browserWindow?.isMiniaturized ?? false
        self.isBrowserWindow = isBrowserWindow
        self.currentEventType = currentEventType
        self.keyWindow = keyWindow
        self.orderedWindows = orderedWindows
        self.isActive = isActive
        self.bringBack = bringBack
        observe()
    }

    private func observe() {
        let center = NotificationCenter.default
        // Un-minimized by the link's handling after the guard began.
        if let browserWindow {
            observers.append(center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification, object: browserWindow, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !Self.isUserEvent(self.currentEventType()) else { return }
                    self.wasMiniaturized = true
                }
            })
        }
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil
        ) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                self.handle(.windowBecameKey(isBrowserWindow: self.isBrowserWindow(window)))
            }
        })
        // Little Ombre covered, or a browser window uncovered: a window
        // went above or below another.
        observers.append(center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: nil
        ) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let window,
                      window === self.littleWindow || self.isBrowserWindow(window)
                else { return }
                self.handle(.settled)
            }
        })
        observeActivation()
        LinkLog.notice("window order at the link: \(orderDescription)") // not shown
        scheduleChecks()
    }

    /// Ombre becoming active (checked), or leaving (the guard ends).
    private func observeActivation() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                LinkLog.notice("Ombre active after the link: \(self.orderDescription)") // not shown
                self.handle(.settled)
            }
        })
        // Ombre left after the link: the user went to another app, never
        // pulled back.
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isOver else { return }
                LinkLog.notice("Little Ombre front guard ended: Ombre no longer active") // not shown
                self.stop()
            }
        })
    }

    /// Checks once the link's handling is done, then 0.5 s and 1 s after
    /// the link; ends the guard after `duration`.
    private func scheduleChecks() {
        // Once the link's handling is done (SwiftUI's own included).
        DispatchQueue.main.async { [weak self] in
            guard let self, isActive() else { return }
            handle(.settled)
        }
        checking = Task { @MainActor [weak self] in
            var waited = Duration.zero
            for check in Self.checks {
                try? await Task.sleep(for: check - waited)
                waited = check
                guard let self, !isOver else { return }
                let when = check.formatted(.units(allowed: [.seconds, .milliseconds])) // not shown
                LinkLog.notice("window order \(when) after the link: \(orderDescription)") // not shown
                handle(.settled)
            }
            try? await Task.sleep(for: Self.duration - waited)
            self?.stop()
        }
    }

    /// Little Ombre (or a sheet of its page) is the key window, and no
    /// browser window is above it.
    private var littleIsInFront: Bool {
        guard let littleWindow else { return true }
        let key = keyWindow()
        let isKey = key.map { Self.belongs($0, to: littleWindow) } ?? false
        return isKey && Self.isAbove(littleWindow, in: orderedWindows(), isBrowserWindow: isBrowserWindow)
    }

    /// `little` comes before every browser window in `order` (front to back).
    static func isAbove(
        _ little: NSWindow, in order: [NSWindow], isBrowserWindow: @MainActor (NSWindow) -> Bool
    ) -> Bool {
        let first = order.first { belongs($0, to: little) || isBrowserWindow($0) }
        return first.map { belongs($0, to: little) } ?? false
    }

    /// `window` is `little`, a sheet of its page or one of its child windows.
    static func belongs(_ window: NSWindow, to little: NSWindow) -> Bool {
        var current: NSWindow? = window
        while let candidate = current {
            if candidate === little { return true }
            current = candidate.sheetParent ?? candidate.parent
        }
        return false
    }

    /// Ombre's windows front to back, and the key one, for the log: their
    /// kind only (a title would show a site).
    private var orderDescription: String {
        let key = keyWindow()
        let windows = orderedWindows().map { window in
            let kind = if window === littleWindow {
                "Little Ombre" // not shown
            } else if isBrowserWindow(window) {
                "browser window" // not shown
            } else {
                "other (\(String(describing: type(of: window))))" // not shown
            }
            return window === key ? "\(kind) [key]" : kind // not shown
        }
        let active = isActive() ? "active" : "inactive" // not shown
        return "\(active), \(windows.isEmpty ? "none" : windows.joined(separator: ", "))" // not shown
    }

    func handle(_ change: Change) {
        guard !isOver else { return }
        guard littleWindow != nil else {
            stop()
            return
        }
        // Ombre not active yet: its activation, still to come, is checked.
        guard isActive() else { return }
        let byUser = Self.isUserEvent(currentEventType())
        switch Self.response(
            to: change, littleIsInFront: littleIsInFront, byUser: byUser, elapsed: .now - start
        ) {
        case .keep:
            break
        case .stop:
            if byUser { LinkLog.notice("Little Ombre front guard ended: the user chose a window") } // not shown
            stop()
        case .bringBack:
            guard bringBacks < Self.maximumBringBacks else {
                LinkLog.notice("Little Ombre front guard ended: brought back too often") // not shown
                stop()
                return
            }
            bringBacks += 1
            let minimizedAgain = restoreMinimized()
            let again = minimizedAgain ? ", browser window minimized again" : "" // not shown
            let before = orderDescription
            LinkLog.notice("Little Ombre brought back in front after the link\(again); was \(before)") // not shown
            bringBack()
            LinkLog.notice("window order now: \(orderDescription)") // not shown
        }
    }

    /// The browser window was minimized before the link: back to the Dock.
    private func restoreMinimized() -> Bool {
        guard wasMiniaturized, let browserWindow, !browserWindow.isMiniaturized else { return false }
        browserWindow.miniaturize(nil)
        return true
    }

    func stop() {
        guard !isOver else { return }
        isOver = true
        checking?.cancel()
        checking = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }
}
