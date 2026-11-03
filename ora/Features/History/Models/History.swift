import Foundation
import SwiftData

/// SwiftData model for a browsing history entry
@Model
final class History {
    // Visits are looked up by address, and listed most recent first.
    #Index<History>([\.urlString], [\.lastAccessedAt])

    @Attribute(.unique) var id: UUID
    var url: URL
    var urlString: String
    var title: String
    var faviconURL: URL
    var faviconLocalFile: URL?
    var createdAt: Date
    var visitCount: Int
    var lastAccessedAt: Date

    @Relationship(inverse: \TabContainer.history) var container: TabContainer?

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        faviconURL: URL,
        faviconLocalFile: URL? = nil,
        createdAt: Date,
        lastAccessedAt: Date,
        visitCount: Int,
        container: TabContainer? = nil
    ) {
        self.id = id
        self.url = url
        self.urlString = url.absoluteString
        self.title = title
        self.faviconURL = faviconURL
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.visitCount = visitCount
        self.faviconLocalFile = faviconLocalFile
        self.container = container
    }
}
