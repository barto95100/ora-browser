import Foundation
import SwiftData

// The models of V1 and V2 as they were stored, frozen: SwiftData recognizes
// a database's version by them. Never change them; a new version gets the
// current classes (see `OmbreSchemaV3`). Only stored properties, their
// attributes and relationships matter here: no behaviour.
//
// `Download` and `TabGroup`, unchanged since and linked to no other model,
// are still the current classes.

extension OmbreSchemaV1 {
    @Model
    final class Tab {
        @Attribute(.unique) var id: UUID
        var url: URL
        var urlString: String
        var savedURL: URL?
        var title: String
        var favicon: URL?
        var createdAt: Date
        var lastAccessedAt: Date?
        var type: TabType
        var order: Int
        var faviconLocalFile: URL?
        var backgroundColorHex: String = "#000000"
        var fileBookmark: Data?
        var splitRightTabID: UUID?
        var splitFraction: Double = 0.5
        var folderID: UUID?
        @Relationship(inverse: \TabContainer.tabs) var parentContainer: TabContainer?

        init(id: UUID = UUID(), url: URL, title: String, type: TabType, order: Int, container: TabContainer) {
            self.id = id
            self.url = url
            urlString = url.absoluteString
            self.title = title
            createdAt = Date()
            lastAccessedAt = Date()
            self.type = type
            self.order = order
            parentContainer = container
        }
    }

    @Model
    final class TabContainer {
        @Attribute(.unique) var id: UUID
        var name: String
        var emoji: String
        var iconSymbol: String?
        var colorName: String?
        var themeName: String?
        var createdAt: Date
        var lastAccessedAt: Date
        var order: Int = 0
        @Relationship(deleteRule: .cascade) var tabs: [Tab] = []
        @Relationship(deleteRule: .cascade) var folders: [Folder] = []
        @Relationship(deleteRule: .cascade, inverse: \SpaceTask.container) var tasks: [SpaceTask] = []
        @Relationship(deleteRule: .cascade) var history: [History] = []

        init(id: UUID = UUID(), name: String, emoji: String = "") {
            self.id = id
            self.name = name
            self.emoji = emoji
            createdAt = Date()
            lastAccessedAt = Date()
        }
    }

    @Model
    final class Folder {
        @Attribute(.unique) var id: UUID
        var name: String
        var isOpened: Bool
        var order: Int = 0
        var parentID: UUID?
        @Relationship(inverse: \TabContainer.folders) var parentContainer: TabContainer?

        init(id: UUID = UUID(), name: String, isOpened: Bool = false, container: TabContainer) {
            self.id = id
            self.name = name
            self.isOpened = isOpened
            parentContainer = container
        }
    }

    @Model
    final class SpaceTask {
        @Attribute(.unique) var id: UUID
        var title: String
        var isDone: Bool
        var createdAt: Date
        var completedAt: Date?
        var dueDate: Date?
        var reminderDate: Date?
        var pageURLString: String?
        var pageTitle: String?
        var order: Int
        var container: TabContainer?
        var parent: SpaceTask?
        @Relationship(deleteRule: .cascade, inverse: \SpaceTask.parent) var subtasks: [SpaceTask] = []

        init(title: String, order: Int) {
            id = UUID()
            self.title = title
            isDone = false
            createdAt = Date()
            self.order = order
        }
    }

    @Model
    final class History {
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

        init(url: URL, title: String, visitCount: Int) {
            id = UUID()
            self.url = url
            urlString = url.absoluteString
            self.title = title
            faviconURL = url
            createdAt = Date()
            self.visitCount = visitCount
            lastAccessedAt = Date()
        }
    }
}
