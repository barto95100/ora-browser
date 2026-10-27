import Foundation
import SwiftData

// MARK: - TabContainer

@Model
class TabContainer: ObservableObject, Identifiable {
    var id: UUID
    var name: String
    var emoji: String
    var createdAt: Date
    var lastAccessedAt: Date

    @Relationship(deleteRule: .cascade) var tabs: [Tab] = []
    @Relationship(deleteRule: .cascade) var folders: [Folder] = []
    @Relationship var history: [History] = []

    init(
        id: UUID = UUID(),
        name: String = "Default",
        isActive: Bool = true,
        emoji: String = "💩"
    ) {
        let nowDate = Date()
        self.id = id
        self.name = name
        self.emoji = emoji
        self.createdAt = nowDate
        self.lastAccessedAt = nowDate
    }

    /// Moves a tab onto another one, in the other's section (favorites,
    /// pinned or normal), like a list: dragged down it goes after the target,
    /// dragged up before it. Only that section's tabs are renumbered, so the
    /// other sections never move.
    func moveTab(_ moved: Tab, onto target: Tab) {
        guard moved.id != target.id else { return }

        // Display order: highest order first (see the sidebar lists).
        let section = tabs
            .filter { $0.type == target.type && $0.id != moved.id }
            .sorted { $0.order > $1.order }
        var ids = section.map(\.id)
        if moved.type == target.type {
            // Keep its place in the list, so moving down lands after the target.
            let position = section.firstIndex { $0.order < moved.order } ?? ids.count
            ids.insert(moved.id, at: position)
        } else {
            // From another section: it takes the target's place, before it.
            moved.switchSections(from: moved, to: target)
        }
        let orderedIDs = TabReordering.reordered(ids, moving: moved.id, onto: target.id)
        let tabsByID = Dictionary((section + [moved]).map { ($0.id, $0) }) { first, _ in first }
        for (index, id) in orderedIDs.enumerated() {
            tabsByID[id]?.order = orderedIDs.count - index
        }
    }
}

/// Reordering of a section's tabs, in display order.
enum TabReordering {
    /// `ids` with `moving` placed at `target`'s position: after it when moving
    /// down, before it when moving up.
    static func reordered(_ ids: [UUID], moving: UUID, onto target: UUID) -> [UUID] {
        guard moving != target, let targetIndex = ids.firstIndex(of: target) else { return ids }
        var result = ids
        if let movingIndex = result.firstIndex(of: moving) {
            result.remove(at: movingIndex)
        }
        result.insert(moving, at: min(targetIndex, result.count))
        return result
    }
}
