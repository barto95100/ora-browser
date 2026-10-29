import Foundation
import SwiftData

extension HistoryManager {
    /// The icon of a site, from its latest page in the history (already on
    /// disk, nothing is downloaded).
    func siteIcon(for domain: String) -> SiteIcon? {
        var descriptor = FetchDescriptor<History>(
            predicate: #Predicate { $0.urlString.contains(domain) },
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        let ofSite = entries.filter { BrowsingTime.domain(of: $0.url) == domain }
        guard let entry = ofSite.first(where: { $0.faviconLocalFile != nil }) ?? ofSite.first else { return nil }
        return SiteIcon(url: entry.faviconURL, localFile: entry.faviconLocalFile)
    }
}

struct SiteIcon: Equatable {
    let url: URL
    let localFile: URL?
}
