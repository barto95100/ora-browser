import AppKit

/// What ⌘Q does (Settings › General › To Quit).
enum QuitBehavior: String, CaseIterable, Identifiable {
    /// Quits once ⌘Q is held about a second, like Arc and Chrome; a short
    /// press only says so.
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

/// Holding ⌘Q: quits only if the key is still held when the delay ends;
/// releasing it before does nothing. Each press has its own token, so a
/// delay from an earlier press never quits.
struct QuitHold {
    static let duration: TimeInterval = 1

    private(set) var isHolding = false
    private var token = 0

    /// A press: the token of the delay to start, nil while a hold goes on
    /// (the held key repeats).
    mutating func pressed() -> Int? {
        guard !isHolding else { return nil }
        isHolding = true
        token += 1
        return token
    }

    /// The key or ⌘ was released, or Ombre went to the background: whether
    /// a hold was going on (to cancel).
    mutating func released() -> Bool {
        defer { isHolding = false }
        return isHolding
    }

    /// How a delay ended.
    enum Ending: Equatable {
        /// From an earlier press: nothing to do.
        case stale
        /// The hold is over, without quitting (the keys were let go).
        case cancelled
        case quit
    }

    /// The delay of `token` ended: quit if ⌘ and the key are still held.
    mutating func elapsed(_ token: Int, isStillHeld: Bool) -> Ending {
        guard isHolding, token == self.token else { return .stale }
        isHolding = false
        return isStillHeld ? .quit : .cancelled
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
