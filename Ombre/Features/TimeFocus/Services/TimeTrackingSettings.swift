import Foundation

/// Settings of the browsing time (Settings › Time & Focus).
@MainActor
final class TimeTrackingSettings: ObservableObject {
    static let shared = TimeTrackingSettings()

    static let retentionChoices = [7, 30, 90, 365]

    private let defaults = UserDefaults.standard
    private static let enabledKey = "timeTracking.enabled"
    private static let retentionKey = "timeTracking.retentionDays"

    /// Whether the time on sites is counted; on by default.
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            BrowsingTimeTracker.shared.refresh()
        }
    }

    /// How many days are kept.
    @Published var retentionDays: Int {
        didSet {
            defaults.set(retentionDays, forKey: Self.retentionKey)
            BrowsingTimeStore.shared.purge(keepingDays: retentionDays)
        }
    }

    private init() {
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let days = defaults.integer(forKey: Self.retentionKey)
        retentionDays = days > 0 ? days : 30
    }
}
