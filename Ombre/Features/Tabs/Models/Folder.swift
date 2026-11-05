import Foundation
import SwiftData

// MARK: - Folder

@Model
class Folder: ObservableObject, Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var isOpened: Bool
    /// Place in the pinned section, shared with the pinned tabs outside
    /// folders (see `TabFolders`).
    var order: Int = 0
    /// The folder it is in; nil: the pinned section itself.
    var parentID: UUID?

    /// The space, optional in the database like `Tab.parentContainer`.
    @Relationship(inverse: \TabContainer.folders) var parentContainer: TabContainer?

    /// The folder's space. Never read it on a deleted folder.
    var container: TabContainer {
        get {
            guard let parentContainer else { preconditionFailure("Folder \(id) has no space: it was deleted") }
            return parentContainer
        }
        set { parentContainer = newValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        isOpened: Bool = false,
        container: TabContainer
    ) {
        self.id = id
        self.name = name
        self.isOpened = isOpened
        self.parentContainer = container
    }
}

extension Folder {
    /// Another window saved this folder: tells the views reading it (see `Tab`).
    func noteChangedElsewhere() {
        note(\.name)
        note(\.isOpened)
        note(\.order)
        note(\.parentID)
        note(\.parentContainer)
    }

    private func note(_ keyPath: KeyPath<Folder, some Any>) {
        _$observationRegistrar.withMutation(of: self, keyPath: keyPath) {}
    }
}
