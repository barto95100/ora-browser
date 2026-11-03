import Foundation
import SwiftData

/// The icon of a site, from its latest page in the history (already on disk,
/// nothing is downloaded).
struct SiteIcon: Equatable {
    let url: URL
    let localFile: URL?

    /// Read from the window's data (`\.modelContext`): the settings window
    /// has no `HistoryManager`.
    static func find(for domain: String, in context: ModelContext) -> SiteIcon? {
        var descriptor = FetchDescriptor<History>(
            predicate: #Predicate { $0.urlString.contains(domain) },
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        let entries = ((try? context.fetch(descriptor)) ?? []).filter { BrowsingTime.domain(of: $0.url) == domain }
        guard let entry = entries.first(where: { $0.faviconLocalFile != nil }) ?? entries.first else { return nil }
        return SiteIcon(url: entry.faviconURL, localFile: entry.faviconLocalFile)
    }
}
