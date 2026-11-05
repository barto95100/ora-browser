import Foundation
import os
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

/// The browsing time, in its own database (`Ombre/BrowsingTime.sqlite`): kept
/// apart from tabs and history, it can be cleared without touching them.
/// Private windows are never counted.
@MainActor
final class BrowsingTimeStore: ObservableObject {
    static let shared = BrowsingTimeStore()

    /// Changes at each save, for the dashboard to follow.
    @Published private(set) var revision = 0

    private let context: ModelContext?

    private init() {
        let folder = OmbreDataFolder.applicationSupport
        let configuration = ModelConfiguration(
            "BrowsingTime",
            schema: Schema([BrowsingTimeRecord.self]),
            url: folder.appending(path: "BrowsingTime.sqlite")
        )
        do {
            let container = try ModelContainer(for: BrowsingTimeRecord.self, configurations: configuration)
            context = ModelContext(container)
        } catch {
            // Browsing time is then not counted: said, not silent.
            // The description may hold the file's path: private.
            let nsError = error as NSError
            Logger(category: "BrowsingTime").error(
                """
                Browsing time database failed to open: \
                \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public) \
                \(String(describing: error), privacy: .private)
                """
            )
            context = nil
        }
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
        context.deleteOrLog(BrowsingTimeRecord.self, where: #Predicate { $0.hour < limit }, "purge browsing time")
        save()
    }

    func delete(domain: String) {
        guard let context else { return }
        context.deleteOrLog(BrowsingTimeRecord.self, where: #Predicate { $0.domain == domain }, "delete site time")
        save()
    }

    /// A space deleted: its time goes too.
    func delete(spaceID: UUID) {
        guard let context else { return }
        context.deleteOrLog(BrowsingTimeRecord.self, where: #Predicate { $0.spaceID == spaceID }, "delete space time")
        save()
    }

    func deleteAll() {
        guard let context else { return }
        context.deleteOrLog(BrowsingTimeRecord.self, "delete all browsing time")
        save()
    }

    private func save() {
        context?.saveOrLog("browsing time")
        revision += 1
    }
}
