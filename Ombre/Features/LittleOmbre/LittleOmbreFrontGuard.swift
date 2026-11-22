import AppKit

/// A link from another app: Little Ombre opens in front with the keyboard,
/// but what follows the link can put the browser window it came from back in
/// front (SwiftUI orders the window that took the link front, un-minimizing
/// it; the app's activation comes after). For a moment after the link, a
/// browser window made key without the user (no click or key typed then)
/// gives the front back to Little Ombre, and goes back to the Dock if it was
/// minimized. A click, a key, "Open in Ombre" or a tab opened from Little
/// Ombre end it: the user's choice is kept.
@MainActor
final class LittleOmbreFrontGuard {
    /// How long after the link the guard watches.
    nonisolated static let duration: Duration = .seconds(2)

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
    private let isActive: @MainActor () -> Bool
    private let bringBack: @MainActor () -> Void
    private var observers: [NSObjectProtocol] = []
    private(set) var isOver = false

    init(
        little littleWindow: NSWindow,
        browserWindow: NSWindow?,
        isBrowserWindow: @escaping @MainActor (NSWindow) -> Bool = { BrowserWindows.browsing.contains($0) },
        currentEventType: @escaping @MainActor () -> NSEvent.EventType? = { NSApp.currentEvent?.type },
        keyWindow: @escaping @MainActor () -> NSWindow? = { NSApp.keyWindow },
        isActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
        bringBack: @escaping @MainActor () -> Void
    ) {
        self.littleWindow = littleWindow
        self.browserWindow = browserWindow
        wasMiniaturized = browserWindow?.isMiniaturized ?? false
        self.isBrowserWindow = isBrowserWindow
        self.currentEventType = currentEventType
        self.keyWindow = keyWindow
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
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                LinkLog.notice("Ombre active after the link: key window \(self.keyWindowKind)") // not shown
                self.handle(.settled)
            }
        })
        // Once the link's handling is done (SwiftUI's own included).
        DispatchQueue.main.async { [weak self] in
            guard let self, isActive() else { return }
            handle(.settled)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.duration)
            self?.stop()
        }
    }

    /// Little Ombre (or a sheet of its page) is the key window.
    private var littleIsInFront: Bool {
        guard let littleWindow else { return true }
        let key = keyWindow()
        return key === littleWindow || (key != nil && key?.sheetParent === littleWindow)
    }

    /// The key window, for the log.
    private var keyWindowKind: String {
        guard let key = keyWindow() else { return "none" } // not shown
        if key === littleWindow { return "Little Ombre" } // not shown
        return isBrowserWindow(key) ? "browser window" : "other" // not shown
    }

    func handle(_ change: Change) {
        guard !isOver else { return }
        guard littleWindow != nil else {
            stop()
            return
        }
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
            let minimizedAgain = restoreMinimized()
            let again = minimizedAgain ? ", browser window minimized again" : "" // not shown
            LinkLog.notice("Little Ombre brought back in front after the link\(again)") // not shown
            bringBack()
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
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }
}
