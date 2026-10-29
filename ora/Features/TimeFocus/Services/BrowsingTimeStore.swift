import Foundation
import SwiftData

/// An hour of a site in a space, in seconds.
@Model
final class BrowsingTimeRecord {
    var spaceID: UUID
    var domain: String
    var hour: Date
    var seconds: Double
    var opens: Int = 0

    init(spaceID: UUID, domain: String, hour: Date, seconds: Double) {
        self.spaceID = spaceID
        self.domain = domain
        self.hour = hour
        self.seconds = seconds
    }
}

/// The browsing time, in its own database (`Ora/BrowsingTime.sqlite`): kept
/// apart from tabs and history, it can be cleared without touching them.
/// Private windows are never counted.
@MainActor
final class BrowsingTimeStore: ObservableObject {
    static let shared = BrowsingTimeStore()

    /// Changes at each save, for the dashboard to follow.
    @Published private(set) var revision = 0

    private let context: ModelContext?

    private init() {
        let folder = URL.applicationSupportDirectory.appending(path: "Ora", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            "BrowsingTime",
            schema: Schema([BrowsingTimeRecord.self]),
            url: folder.appending(path: "BrowsingTime.sqlite")
        )
        let container = try? ModelContainer(for: BrowsingTimeRecord.self, configurations: configuration)
        context = container.map { ModelContext($0) }
    }

    /// Time spent on a site, from `start` to `end`; `opened`: the site has
    /// just come in front.
    func record(from start: Date, to end: Date, domain: String, spaceID: UUID, opened: Bool = false) {
        guard let context else { return }
        for (index, slice) in BrowsingTime.hourSlices(from: start, to: end).enumerated() {
            let opens = opened && index == 0 ? 1 : 0
            let hour = slice.hour
            var descriptor = FetchDescriptor<BrowsingTimeRecord>(
                predicate: #Predicate { $0.spaceID == spaceID && $0.domain == domain && $0.hour == hour }
            )
            descriptor.fetchLimit = 1
            if let record = try? context.fetch(descriptor).first {
                record.seconds += slice.seconds
                record.opens += opens
            } else {
                let record = BrowsingTimeRecord(spaceID: spaceID, domain: domain, hour: hour, seconds: slice.seconds)
                record.opens = opens
                context.insert(record)
            }
        }
        save()
    }

    func entries(in interval: DateInterval) -> [BrowsingTimeEntry] {
        guard let context else { return [] }
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<BrowsingTimeRecord>(
            predicate: #Predicate { $0.hour >= start && $0.hour < end }
        )
        return ((try? context.fetch(descriptor)) ?? []).map { record in
            BrowsingTimeEntry(
                spaceID: record.spaceID,
                domain: record.domain,
                hour: record.hour,
                seconds: record.seconds,
                opens: record.opens
            )
        }
    }

    /// Forgets what is older than `days` days.
    func purge(keepingDays days: Int, now: Date = Date()) {
        guard let context, let limit = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return }
        try? context.delete(model: BrowsingTimeRecord.self, where: #Predicate { $0.hour < limit })
        save()
    }

    func delete(domain: String) {
        guard let context else { return }
        try? context.delete(model: BrowsingTimeRecord.self, where: #Predicate { $0.domain == domain })
        save()
    }

    /// A space deleted: its time goes too.
    func delete(spaceID: UUID) {
        guard let context else { return }
        try? context.delete(model: BrowsingTimeRecord.self, where: #Predicate { $0.spaceID == spaceID })
        save()
    }

    func deleteAll() {
        guard let context else { return }
        try? context.delete(model: BrowsingTimeRecord.self)
        save()
    }

    private func save() {
        try? context?.save()
        revision += 1
    }
}
