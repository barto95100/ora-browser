import Foundation
import os.log
import SwiftData

private let logger = Logger(category: "HistoryManager")

@MainActor
class HistoryManager: ObservableObject {
    let modelContainer: ModelContainer
    let modelContext: ModelContext

    init(modelContainer: ModelContainer, modelContext: ModelContext) {
        self.modelContainer = modelContainer
        self.modelContext = modelContext
    }

    func record(
        title: String,
        url: URL,
        faviconURL: URL? = nil,
        faviconLocalFile: URL? = nil,
        container: TabContainer
    ) {
        let urlString = url.absoluteString
        let containerId = container.id

        // Keep history entries scoped to a space so visits from different spaces
        // do not overwrite each other or become unreachable from space filters.
        var descriptor = FetchDescriptor<History>(
            predicate: #Predicate { history in
                history.urlString == urlString && history.container?.id == containerId
            },
            sortBy: [.init(\.lastAccessedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.visitCount += 1
            existing.lastAccessedAt = Date() // update last visited time
        } else {
            let now = Date()
            let defaultFaviconURL = FaviconService.shared.faviconURL(for: url.host ?? "")
            let resolvedFaviconURL = faviconURL ?? defaultFaviconURL ?? url
            modelContext.insert(History(
                url: url,
                title: title,
                faviconURL: resolvedFaviconURL,
                faviconLocalFile: faviconLocalFile,
                createdAt: now,
                lastAccessedAt: now,
                visitCount: 1,
                container: container
            ))
        }

        modelContext.saveOrLog("record history visit")
    }

    /// Keeps the latest entry of a page in sync with its title, without
    /// counting a new visit.
    func updateTitle(_ title: String, for url: URL, container: TabContainer) {
        let urlString = url.absoluteString
        let containerId = container.id
        var descriptor = FetchDescriptor<History>(
            predicate: #Predicate { history in
                history.urlString == urlString && history.container?.id == containerId
            },
            sortBy: [.init(\.lastAccessedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard !title.isEmpty,
              let entry = try? modelContext.fetch(descriptor).first,
              entry.title != title
        else { return }

        entry.title = title
        modelContext.saveOrLog("update history title")
    }

    /// The space's entries matching `text` (in the address or the title, as
    /// Safari does), most recent first, at most `limit`. The database does
    /// the filtering: it is called at each key typed in the launcher, and
    /// loading the whole history took 0.3 s with 20 000 entries.
    func search(_ text: String, activeContainerId: UUID, limit: Int) -> [History] {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        var descriptor = FetchDescriptor<History>(
            predicate: trimmedText.isEmpty
                ? #Predicate { $0.container?.id == activeContainerId }
                : #Predicate
            {
                $0.container?.id == activeContainerId && (
                    $0.urlString.localizedStandardContains(trimmedText) ||
                        $0.title.localizedStandardContains(trimmedText)
                )
            },
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.error("Error fetching history: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func delete(_ entry: History) {
        modelContext.delete(entry)
        modelContext.saveOrLog("delete history entry")
    }

    /// Removes the space's pages visited within the range. An entry keeps only
    /// a page's last visit, so a page visited again in the range goes entirely.
    func clear(_ range: HistoryClearRange, in container: TabContainer) {
        let containerId = container.id
        let start = range.startDate() ?? .distantPast
        let descriptor = FetchDescriptor<History>(
            predicate: #Predicate { $0.container?.id == containerId && $0.lastAccessedAt >= start }
        )
        do {
            for history in try modelContext.fetch(descriptor) {
                modelContext.delete(history)
            }
            try modelContext.save()
        } catch {
            logger.error("Failed to clear history: \(String(describing: error), privacy: .public)")
        }
    }

    func clearContainerHistory(_ container: TabContainer) {
        let containerId = container.id
        let descriptor = FetchDescriptor<History>(
            predicate: #Predicate { $0.container?.id == containerId }
        )

        do {
            let histories = try modelContext.fetch(descriptor)

            for history in histories {
                modelContext.delete(history)
            }

            try modelContext.save()
        } catch {
            logger.error("Failed to clear history for container \(container.id): \(error.localizedDescription)")
        }
    }
}
