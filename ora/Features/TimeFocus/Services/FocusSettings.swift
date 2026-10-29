import Foundation

/// Settings of focus (Settings › Time & Focus), its sites blocked per space
/// and the focus time of each day (for the daily goal).
@MainActor
final class FocusSettings: ObservableObject {
    static let shared = FocusSettings()

    static let durationChoices = [15, 25, 45, 60, 90]
    static let goalChoices = [0, 30, 60, 120, 180, 240]

    private let defaults = UserDefaults.standard

    @Published var focusMinutes: Int {
        didSet { defaults.set(focusMinutes, forKey: Keys.focus) }
    }

    @Published var breakMinutes: Int {
        didSet { defaults.set(breakMinutes, forKey: Keys.shortBreak) }
    }

    @Published var longBreakMinutes: Int {
        didSet { defaults.set(longBreakMinutes, forKey: Keys.longBreak) }
    }

    @Published var cyclesBeforeLongBreak: Int {
        didSet { defaults.set(cyclesBeforeLongBreak, forKey: Keys.cycles) }
    }

    @Published var repeats: Bool {
        didSet { defaults.set(repeats, forKey: Keys.repeats) }
    }

    /// Minutes of focus wanted per day; 0: no goal.
    @Published var dailyGoalMinutes: Int {
        didSet { defaults.set(dailyGoalMinutes, forKey: Keys.goal) }
    }

    /// Space id → sites blocked during focus.
    @Published private(set) var blockedSites: [String: [String]] {
        didSet { save(blockedSites, forKey: Keys.blocked) }
    }

    /// "yyyy-MM-dd" → seconds of focus that day.
    @Published private(set) var focusSecondsByDay: [String: Double] {
        didSet { save(focusSecondsByDay, forKey: Keys.days) }
    }

    var plan: FocusPlan {
        FocusPlan(
            focusMinutes: focusMinutes,
            breakMinutes: breakMinutes,
            longBreakMinutes: longBreakMinutes,
            cyclesBeforeLongBreak: cyclesBeforeLongBreak,
            repeats: repeats
        )
    }

    private enum Keys {
        static let focus = "focus.minutes"
        static let shortBreak = "focus.breakMinutes"
        static let longBreak = "focus.longBreakMinutes"
        static let cycles = "focus.cyclesBeforeLongBreak"
        static let repeats = "focus.repeats"
        static let goal = "focus.dailyGoalMinutes"
        static let blocked = "focus.blockedSites"
        static let days = "focus.secondsByDay"
    }

    private init() {
        let defaults = UserDefaults.standard
        func integer(_ key: String, _ fallback: Int) -> Int {
            let value = defaults.integer(forKey: key)
            return value > 0 ? value : fallback
        }
        focusMinutes = integer(Keys.focus, 25)
        breakMinutes = integer(Keys.shortBreak, 5)
        longBreakMinutes = integer(Keys.longBreak, 15)
        cyclesBeforeLongBreak = integer(Keys.cycles, 4)
        repeats = defaults.bool(forKey: Keys.repeats)
        dailyGoalMinutes = defaults.integer(forKey: Keys.goal)
        blockedSites = Self.load(Keys.blocked) ?? [:]
        focusSecondsByDay = Self.load(Keys.days) ?? [:]
    }

    // MARK: - Blocked sites

    func blockedSites(in spaceID: UUID) -> [String] {
        blockedSites[spaceID.uuidString] ?? []
    }

    /// Adds what the user typed, as a site; false if it is not one.
    @discardableResult
    func block(_ input: String, in spaceID: UUID) -> Bool {
        guard let site = FocusBlocking.site(from: input) else { return false }
        var sites = blockedSites(in: spaceID)
        guard !sites.contains(site) else { return true }
        sites.append(site)
        blockedSites[spaceID.uuidString] = sites.sorted()
        return true
    }

    func unblock(_ site: String, in spaceID: UUID) {
        blockedSites[spaceID.uuidString] = blockedSites(in: spaceID).filter { $0 != site }
    }

    /// A space deleted: its list goes too.
    func removeSpace(_ spaceID: UUID) {
        blockedSites[spaceID.uuidString] = nil
    }

    // MARK: - Focus time per day

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func focusSeconds(on date: Date = Date()) -> Double {
        focusSecondsByDay[Self.dayKey(for: date)] ?? 0
    }

    func addFocus(_ seconds: Double, on date: Date = Date()) {
        guard seconds > 0 else { return }
        focusSecondsByDay[Self.dayKey(for: date), default: 0] += seconds
        // Kept a year.
        if focusSecondsByDay.count > 366 {
            let oldest = focusSecondsByDay.keys.sorted().prefix(focusSecondsByDay.count - 366)
            oldest.forEach { focusSecondsByDay[$0] = nil }
        }
    }

    // MARK: - Storage

    private func save(_ value: some Encodable, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<Value: Decodable>(_ key: String) -> Value? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
