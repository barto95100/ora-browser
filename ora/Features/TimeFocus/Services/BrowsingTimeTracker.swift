import AppKit
import CoreGraphics

/// Counts the time spent on sites: the page of the active tab of the window
/// in front, while Ora is in front and the user is there (some input in the
/// last 2 minutes, or the page plays media). Private windows are not counted.
///
/// Counted by stretches, ended when what is in front changes (app, window,
/// tab, address) and saved every 30 seconds; no timer while Ora is not in front.
@MainActor
final class BrowsingTimeTracker {
    static let shared = BrowsingTimeTracker()

    /// Without input for longer, the user is away (unless media plays).
    static let idleLimit: TimeInterval = 120
    private static let tickInterval: TimeInterval = 30

    private struct Registration {
        weak var window: NSWindow?
        weak var tabManager: TabManager?
    }

    private struct Target: Equatable {
        let spaceID: UUID
        let domain: String
    }

    private var registrations: [Registration] = []
    private var target: Target?
    private var segmentStart: Date?
    /// The last site in front: coming back to it is not a new opening.
    private var lastDomain: String?
    private var isOpening = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isScreenAsleep = false

    /// A normal window and its tabs.
    func register(_ window: NSWindow, tabManager: TabManager) {
        registrations.removeAll { $0.window == nil || $0.window === window }
        registrations.append(Registration(window: window, tabManager: tabManager))
        if observers.isEmpty {
            observe()
            BrowsingTimeStore.shared.purge(keepingDays: TimeTrackingSettings.shared.retentionDays)
        }
        refresh()
    }

    /// What is in front may have changed: the stretch so far is counted, a
    /// new one starts.
    func refresh() {
        let now = Date()
        flush(until: now)
        start(currentTarget(), at: now)
    }

    // MARK: - Stretches

    private func start(_ next: Target?, at date: Date) {
        if let next, next.domain != lastDomain {
            isOpening = true
            lastDomain = next.domain
        }
        target = next
        segmentStart = next == nil ? nil : date
        updateTimer()
    }

    private func flush(until end: Date) {
        guard let target, let start = segmentStart, end > start else { return }
        BrowsingTimeStore.shared.record(
            from: start, to: end, domain: target.domain, spaceID: target.spaceID, opened: isOpening
        )
        isOpening = false
        segmentStart = end
    }

    /// Every 30 seconds: saved, and stopped at the last input if the user left.
    private func tick() {
        let now = Date()
        let next = currentTarget()
        let idle = Self.idleTime()
        let end = next == nil && idle > Self.idleLimit ? now.addingTimeInterval(-idle) : now
        flush(until: end)
        start(next, at: now)
    }

    private func currentTarget() -> Target? {
        guard TimeTrackingSettings.shared.isEnabled, NSApp.isActive, !isScreenAsleep,
              let window = NSApp.keyWindow,
              let tabManager = registrations.first(where: { $0.window === window })?.tabManager,
              let tab = tabManager.activeTab,
              let domain = BrowsingTime.domain(of: tab.url)
        else { return nil }
        guard Self.idleTime() < Self.idleLimit || tab.isPlayingMedia else { return nil }
        return Target(spaceID: tab.container.id, domain: domain)
    }

    /// Seconds since the last keyboard, mouse or trackpad input.
    private static func idleTime() -> TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    // MARK: - Timer and notifications

    private func updateTimer() {
        let shouldTick = NSApp.isActive && !isScreenAsleep && TimeTrackingSettings.shared.isEnabled
        if shouldTick, timer == nil {
            let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { _ in
                MainActor.assumeIsolated { BrowsingTimeTracker.shared.tick() }
            }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !shouldTick {
            timer?.invalidate()
            timer = nil
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.willTerminateNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { BrowsingTimeTracker.shared.refresh() }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { BrowsingTimeTracker.shared.setScreenAsleep(true) }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { BrowsingTimeTracker.shared.setScreenAsleep(false) }
        })
    }

    private func setScreenAsleep(_ isAsleep: Bool) {
        if isAsleep { flush(until: Date()) }
        isScreenAsleep = isAsleep
        refresh()
    }
}
