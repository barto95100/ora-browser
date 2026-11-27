import AppKit
import CoreGraphics

/// `chrome.idle`, which WebKit lacks: whether the user is active, idle (no
/// input for the extension's detection interval) or the screen is locked,
/// as in Chrome (the interval from 15 s, 60 s by default).
///
/// Watched only while an extension listens to `onStateChanged`: once when
/// the user may become idle, the screen locks or the Mac wakes; every few
/// seconds only while the user is idle (to see them come back).
@MainActor
final class ExtensionIdle {
    /// Where the user's state comes from (the tests give their own).
    struct Source {
        var secondsSinceInput: @MainActor () -> TimeInterval
        var isLocked: @MainActor () -> Bool

        static var system: Source {
            Source(
                secondsSinceInput: {
                    // Any input event (kCGAnyInputEventType).
                    CGEventType(rawValue: ~0).map {
                        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
                    } ?? 0
                },
                isLocked: {
                    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
                    return session?["CGSSessionScreenIsLocked"] as? Bool == true // not shown
                }
            )
        }
    }

    static let defaultInterval = 60
    static let minimumInterval = 15
    /// Chrome's longest: 4 hours.
    static let maximumInterval = 4 * 60 * 60
    /// How often a user who is idle is looked at again.
    static let idleCheck: Duration = .seconds(2)

    var source: Source
    /// The state changed for an extension that listens.
    var stateChanged: (_ extensionID: String, _ state: String) -> Void = { _, _ in }

    private var intervals: [String: Int] = [:]
    /// The extensions that listen, and the state they were told last.
    private var watching: [String: String] = [:]
    private var check: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(source: Source = .system) {
        self.source = source
    }

    func handle(_ method: String, _ details: [String: Any], extensionID: String) throws -> Any? {
        switch method {
        case "queryState":
            guard let seconds = details["detectionIntervalInSeconds"] as? Int else {
                throw ExtensionComplementFailure.invalid("Invalid detectionIntervalInSeconds.") // not shown
            }
            return state(interval: Self.clamped(seconds))
        case "setDetectionInterval":
            guard let seconds = details["intervalInSeconds"] as? Int else {
                throw ExtensionComplementFailure.invalid("Invalid intervalInSeconds.") // not shown
            }
            intervals[extensionID] = Self.clamped(seconds)
            if watching[extensionID] != nil { evaluate() }
            return nil
        case "watch":
            if watching[extensionID] == nil {
                watching[extensionID] = state(interval: interval(of: extensionID))
                observe()
                evaluate()
            }
            return nil
        default:
            throw ExtensionComplementFailure.unknownCall("idle.\(method)")
        }
    }

    static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, minimumInterval), maximumInterval)
    }

    func interval(of extensionID: String) -> Int {
        intervals[extensionID] ?? Self.defaultInterval
    }

    /// "locked", "idle" or "active", as in Chrome.
    func state(interval: Int) -> String {
        if source.isLocked() { return "locked" }
        return source.secondsSinceInput() >= TimeInterval(interval) ? "idle" : "active"
    }

    /// Tells what changed, then waits until something may change.
    func evaluate() {
        check?.cancel()
        check = nil
        guard !watching.isEmpty else { return }
        let locked = source.isLocked()
        let since = source.secondsSinceInput()
        var wait: Duration?
        for (id, told) in watching {
            let interval = interval(of: id)
            let now = locked ? "locked" : (since >= TimeInterval(interval) ? "idle" : "active")
            if now != told {
                watching[id] = now
                stateChanged(id, now)
            }
            // Locked: the unlock says it. Idle: looked at again soon.
            // Active: when it may become idle.
            let next: Duration? = switch now {
            case "active": .milliseconds(Int((TimeInterval(interval) - since) * 1000) + 500)
            case "idle": Self.idleCheck
            default: nil
            }
            if let next { wait = wait.map { min($0, next) } ?? next }
        }
        guard let wait else { return }
        check = Task { [weak self] in
            try? await Task.sleep(for: wait, tolerance: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    /// The extension stopped: no longer watched for it.
    func forget(extensionID: String) {
        watching[extensionID] = nil
        intervals[extensionID] = nil
        if watching.isEmpty {
            check?.cancel()
            check = nil
            for (center, observer) in observers {
                center.removeObserver(observer)
            }
            observers = []
        }
    }

    var isWatching: Bool {
        !watching.isEmpty
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let changed: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            (distributed, distributed.addObserver(
                forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: changed
            )),
            (distributed, distributed.addObserver(
                forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: changed
            )),
            (workspace, workspace.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: changed
            ))
        ]
    }
}
