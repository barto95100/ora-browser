import AppKit
import UserNotifications

/// The focus run going on, for all windows: its phase and when it ends. While
/// focusing, the sites blocked in a tab's space are covered (see
/// `FocusBlockView`); breaks open them again. One timer, at the end of the
/// phase; a macOS notification tells it, even with Ora in the background.
@MainActor
final class FocusSession: ObservableObject {
    static let shared = FocusSession()

    @Published private(set) var phase: FocusPhase?
    @Published private(set) var phaseStart: Date?
    @Published private(set) var phaseEnd: Date?
    /// Focus phases done in this run.
    @Published private(set) var completedCycles = 0
    /// Site → end of its "Allow 5 min".
    @Published private(set) var allowedUntil: [String: Date] = [:]

    private var timer: Timer?
    private static let notificationID = "ora-focus-phase"

    var isRunning: Bool {
        phase != nil
    }

    var isFocusing: Bool {
        phase == .focus
    }

    func remaining(at now: Date = Date()) -> TimeInterval {
        max((phaseEnd ?? now).timeIntervalSince(now), 0)
    }

    /// Done share of the phase (0...1).
    func progress(at now: Date = Date()) -> Double {
        guard let phaseStart, let phaseEnd, phaseEnd > phaseStart else { return 0 }
        return min(max(now.timeIntervalSince(phaseStart) / phaseEnd.timeIntervalSince(phaseStart), 0), 1)
    }

    // MARK: - Actions

    func start() {
        completedCycles = 0
        allowedUntil = [:]
        begin(.focus)
    }

    func stop() {
        countFocus(until: Date())
        finish()
    }

    func skipBreak() {
        begin(.focus)
    }

    /// The site opens for a while despite the focus.
    func allow(_ site: String, minutes: Int = 5) {
        allowedUntil[site] = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Whether the tab's page is covered: focusing, its site blocked in its
    /// space and not allowed for now. Private windows are not.
    func isBlocked(_ tab: Tab, now: Date = Date()) -> Bool {
        guard isFocusing, !tab.isPrivate else { return false }
        return FocusBlocking.isBlocked(
            site: BrowsingTime.domain(of: tab.url),
            blocked: FocusSettings.shared.blockedSites(in: tab.container.id),
            allowedUntil: allowedUntil,
            now: now
        )
    }

    // MARK: - Phases

    private func begin(_ phase: FocusPhase) {
        let now = Date()
        let end = now.addingTimeInterval(FocusSettings.shared.plan.duration(of: phase))
        self.phase = phase
        phaseStart = now
        phaseEnd = end
        if phase != .focus { allowedUntil = [:] }
        schedule(at: end)
        notifyEnd(of: phase, at: end)
    }

    private func phaseEnded() {
        guard let phase else { return }
        if phase == .focus {
            countFocus(until: phaseEnd ?? Date())
            completedCycles += 1
        }
        if let next = FocusSettings.shared.plan.phase(after: phase, completedCycles: completedCycles) {
            begin(next)
        } else {
            finish()
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        phase = nil
        phaseStart = nil
        phaseEnd = nil
        allowedUntil = [:]
    }

    /// The focus time so far counts for the day's goal.
    private func countFocus(until end: Date) {
        guard isFocusing, let phaseStart else { return }
        FocusSettings.shared.addFocus(min(end, phaseEnd ?? end).timeIntervalSince(phaseStart))
        self.phaseStart = end
    }

    private func schedule(at date: Date) {
        timer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { FocusSession.shared.phaseEnded() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func notifyEnd(of phase: FocusPhase, at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        WebNotificationCenter.shared.requestAuthorizationIfNeeded()
        let plan = FocusSettings.shared.plan
        let content = UNMutableNotificationContent()
        switch phase {
        case .focus:
            content.title = "Focus done"
            if let next = plan.phase(after: .focus, completedCycles: completedCycles + 1) {
                content.body = "Time for a \(Int(plan.duration(of: next) / 60)) min break."
            } else {
                content.body = "Well done. Blocked sites are open again."
            }
        case .shortBreak, .longBreak:
            content.title = "Break over"
            content.body = "Back to focus for \(plan.focusMinutes) min."
        }
        content.sound = .default
        content.threadIdentifier = "ora-focus"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSinceNow, 1), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }
}
