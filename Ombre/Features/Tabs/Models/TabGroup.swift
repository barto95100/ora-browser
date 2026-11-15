import Foundation
import SwiftData

/// A group of a space's tabs (not pinned nor favorites), like those of a
/// site: a row with its tabs under it in the sidebar, which can be closed,
/// renamed and ungrouped. It only lists its tabs: their place in the space
/// (`Tab.order`) is theirs, the group shows where its first tab is.
@Model
final class TabGroup {
    enum Kind: String {
        /// The tabs of one site (`siteKey`).
        case site
        /// Tabs of one subject.
        case topic
    }

    @Attribute(.unique) var id: UUID
    /// Its space (no relationship: the space's model stays as it is).
    var spaceID: UUID
    var name: String
    var isCollapsed: Bool = false
    var kindRaw: String
    /// The site of a site group (its registrable domain).
    var siteKey: String?
    /// Its tabs.
    var tabIDs: [UUID] = []
    /// Tabs the user took out: never put back automatically.
    var releasedTabIDs: [UUID] = []
    /// Ungrouped by the user: its site isn't grouped again automatically
    /// (Tidy Tabs Now still does). It then lists no tab.
    var isDissolved: Bool = false
    var createdAt: Date

    var kind: Kind {
        Kind(rawValue: kindRaw) ?? .site
    }

    init(id: UUID = UUID(), spaceID: UUID, name: String, kind: Kind, siteKey: String? = nil, tabIDs: [UUID]) {
        self.id = id
        self.spaceID = spaceID
        self.name = name
        kindRaw = kind.rawValue
        self.siteKey = siteKey
        self.tabIDs = tabIDs
        createdAt = Date()
    }
}
