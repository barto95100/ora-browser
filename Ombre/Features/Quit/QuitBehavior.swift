import AppKit

/// What ⌘Q does (Settings › General › To Quit).
enum QuitBehavior: String, CaseIterable, Identifiable {
    /// Like Arc and Chrome: holding ⌘Q fills a ring for about a second,
    /// then Ombre quits on the release; a short press only says so.
    case holdKey
    /// Asks first, with how many windows and tabs will close.
    case ask
    /// Quits at once.
    case immediately

    static let defaultValue = QuitBehavior.holdKey

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .holdKey: String(localized: "Hold ⌘Q")
        case .ask: String(localized: "Ask for Confirmation")
        case .immediately: String(localized: "Quit Immediately")
        }
    }
}

/// What a request to quit leads to.
enum QuitDecision: Equatable {
    /// Quit now.
    case quit
    /// Start (or keep) waiting for ⌘Q to be held.
    case hold
    /// Ask first.
    case ask

    /// Only ⌘Q waits or asks: Ombre › Quit Ombre, the Dock, logging out and
    /// a quit already confirmed quit at once. ⌘Q works the same from any
    /// window: a browser window, Little Ombre, the settings.
    static func decide(behavior: QuitBehavior, isQuitKey: Bool, isConfirmed: Bool) -> QuitDecision {
        guard isQuitKey, !isConfirmed else { return .quit }
        switch behavior {
        case .holdKey: return .hold
        case .ask: return .ask
        case .immediately: return .quit
        }
    }

    /// Whether `event`, the one that asks to quit, is a key press with ⌘
    /// (the menu's shortcut), not a click in the menu. `isAppleEvent`: the
    /// Dock or logging out asks, whatever the last event was.
    static func isQuitKey(_ event: NSEvent?, isAppleEvent: Bool = false) -> Bool {
        guard !isAppleEvent, let event, event.type == .keyDown else { return false }
        return event.modifierFlags.contains(.command)
    }
}

/// Holding ⌘Q: the hint fills for about a second, then says « Release to
/// Quit »; Ombre quits when ⌘ or the key is released after that, never
/// while they are still down (the key's repeats would go on to the app
/// that comes to the front and quit it too). Releasing before the hint is
/// full, or leaving Ombre, does nothing. Each press has its own token, so a
/// delay from an earlier press never arms.
struct QuitHold {
    static let duration: TimeInterval = 1

    enum Phase: Equatable {
        case idle
        /// The hint fills.
        case holding
        /// Full: releasing quits.
        case armed
    }

    private(set) var phase = Phase.idle
    private var token = 0

    var isHolding: Bool {
        phase != .idle
    }

    /// A press: the token of the delay to start, nil for a repeat of the
    /// held key. A new press (not a repeat) while holding means a release
    /// we did not see: it starts again.
    mutating func pressed(isRepeat: Bool = false) -> Int? {
        if isHolding, isRepeat { return nil }
        phase = .holding
        token += 1
        return token
    }

    /// Whether a key event is a repeat of the held key, to absorb: no ⌘Q
    /// reaches the menu again, nor another app.
    func absorbs(keyDownOf keyCode: UInt16, isRepeat: Bool, heldKeyCode: UInt16) -> Bool {
        isHolding && isRepeat && keyCode == heldKeyCode
    }

    /// How a delay ended.
    enum Ending: Equatable {
        /// From an earlier press: nothing to do.
        case stale
        /// The hold is over, without quitting (the keys were let go).
        case cancelled
        /// The hint is full: releasing now quits.
        case armed
    }

    /// The delay of `token` ended: arm if ⌘ and the key are still held.
    mutating func elapsed(_ token: Int, isStillHeld: Bool) -> Ending {
        guard phase == .holding, token == self.token else { return .stale }
        phase = isStillHeld ? .armed : .idle
        return isStillHeld ? .armed : .cancelled
    }

    /// What releasing ⌘ or the key does.
    enum Release: Equatable {
        /// No hold.
        case nothing
        /// Released before the hint was full.
        case cancelled
        case quit
    }

    /// ⌘ or the key was released.
    mutating func released() -> Release {
        defer { phase = .idle }
        switch phase {
        case .idle: return .nothing
        case .holding: return .cancelled
        case .armed: return .quit
        }
    }

    /// Ombre went to the background: whether a hold was going on. It never
    /// quits, even when armed.
    mutating func abandoned() -> Bool {
        defer { phase = .idle }
        return isHolding
    }
}

/// The text of the question to quit.
enum QuitConfirmationText {
    static func message(windows: Int, tabs: Int) -> String {
        let windowsText = String(localized: "\(windows) windows")
        let tabsText = String(localized: "\(tabs) tabs")
        return String(localized: "\(windowsText) and \(tabsText) will close.")
    }
}
