import Foundation
import SwiftData

// MARK: - Folder

@Model
class Folder: ObservableObject, Identifiable {
    var id: UUID
    var name: String
    var isOpened: Bool
    /// Place in the pinned section, shared with the pinned tabs outside
    /// folders (see `TabFolders`).
    var order: Int = 0

    @Relationship(inverse: \TabContainer.folders) var container: TabContainer
    init(
        id: UUID = UUID(),
        name: String,
        isOpened: Bool = false,
        container: TabContainer
    ) {
        self.id = id
        self.name = name
        self.isOpened = isOpened
        self.container = container
    }
}
