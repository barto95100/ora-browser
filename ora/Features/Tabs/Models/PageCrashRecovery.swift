import Foundation

/// The process rendering a page ended unexpectedly (a crash, or macOS reclaiming
/// memory) and Ora stopped reloading it automatically.
struct PageCrashError: LocalizedError {
    var errorDescription: String? {
        "The webpage stopped working because a problem occurred."
    }
}

/// Decides how a tab recovers when the process rendering its page ends, the way
/// Safari does:
/// - the page the user is looking at reloads once, right away;
/// - a page in the background stays unloaded until its tab is shown again, so a
///   crash never wakes up pages nobody is looking at;
/// - a page that ends again shortly after being reloaded is not reloaded again,
///   to avoid a crash loop: the user decides.
struct PageCrashRecoveryPolicy {
    enum Action: Equatable {
        /// Reload the page right away and tell the user why.
        case reloadNow
        /// Leave the page unloaded until its tab is shown again.
        case reloadWhenShown
        /// Stop reloading and show the crash page.
        case showCrashPage
    }

    /// A crash this soon after a reload counts as a repeated crash.
    static let repeatedCrashInterval: TimeInterval = 30

    /// Whether the page is waiting for its tab to be shown to reload.
    private(set) var isPendingReload = false
    private var lastReloadDate: Date?

    /// Called when the process rendering the page has ended.
    mutating func processDidTerminate(isVisible: Bool, now: Date = Date()) -> Action {
        if let lastReloadDate, now.timeIntervalSince(lastReloadDate) < Self.repeatedCrashInterval {
            isPendingReload = false
            return .showCrashPage
        }

        guard isVisible else {
            isPendingReload = true
            return .reloadWhenShown
        }

        recordReload(at: now)
        return .reloadNow
    }

    /// Called when the tab is shown. Returns whether its page must reload now.
    mutating func tabDidBecomeVisible(now: Date = Date()) -> Bool {
        guard isPendingReload else { return false }
        recordReload(at: now)
        return true
    }

    /// Records a reload of the crashed page, automatic or asked by the user.
    mutating func recordReload(at now: Date = Date()) {
        isPendingReload = false
        lastReloadDate = now
    }
}
