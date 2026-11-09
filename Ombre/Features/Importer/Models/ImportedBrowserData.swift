import Foundation

/// What another browser holds, read before anything is written to Ombre: spaces
/// with their favorites (Zen's Essentials, Arc's favorites), and their pinned
/// tabs and folders, folders inside folders included.
struct ImportedBrowserData: Equatable, Sendable {
    var spaces: [ImportedSpace]

    var favoriteCount: Int {
        spaces.reduce(0) { $0 + $1.favorites.count }
    }

    var pinnedTabCount: Int {
        spaces.reduce(0) { $0 + ImportedPinnedItem.tabCount(in: $1.pinned) }
    }

    var folderCount: Int {
        spaces.reduce(0) { $0 + ImportedPinnedItem.folderCount(in: $1.pinned) }
    }

    var isEmpty: Bool {
        spaces.allSatisfy { $0.favorites.isEmpty && $0.pinned.isEmpty && $0.history.isEmpty }
    }

    /// The spaces at these positions, in their order; unknown positions are ignored.
    func selecting(_ positions: [Int]) -> ImportedBrowserData {
        ImportedBrowserData(spaces: positions.sorted().filter(spaces.indices.contains).map { spaces[$0] })
    }
}

struct ImportedSpace: Equatable, Sendable {
    var name: String
    /// An emoji, if the browser has one for it.
    var emoji: String?
    var favorites: [ImportedTab] = []
    /// In display order.
    var pinned: [ImportedPinnedItem] = []
    /// Pages visited, most recent first (Safari's profiles have their own).
    var history: [ImportedVisit] = []
}

struct ImportedVisit: Equatable, Sendable {
    var url: URL
    var title: String
    var lastVisit: Date
    var visitCount: Int
}

struct ImportedTab: Equatable, Sendable {
    var url: URL
    var title: String
    var faviconURL: URL?
}

indirect enum ImportedPinnedItem: Equatable, Sendable {
    case tab(ImportedTab)
    case folder(name: String, isOpen: Bool, items: [ImportedPinnedItem])

    static func tabCount(in items: [ImportedPinnedItem]) -> Int {
        items.reduce(0) { count, item in
            switch item {
            case .tab: count + 1
            case let .folder(_, _, items): count + tabCount(in: items)
            }
        }
    }

    /// Every tab, folders' included, in order.
    static func tabs(in items: [ImportedPinnedItem]) -> [ImportedTab] {
        items.flatMap { item -> [ImportedTab] in
            switch item {
            case let .tab(tab): [tab]
            case let .folder(_, _, items): tabs(in: items)
            }
        }
    }

    static func folderCount(in items: [ImportedPinnedItem]) -> Int {
        items.reduce(0) { count, item in
            switch item {
            case .tab: count
            case let .folder(_, _, items): count + 1 + folderCount(in: items)
            }
        }
    }
}
