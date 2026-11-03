import Foundation
import SwiftData

/// The main database's first schema. Every model is listed, including those
/// only reached through relationships.
///
/// The models are the app's current classes. When a change needs a new
/// version, freeze copies of these classes inside this enum, add
/// `OmbreSchemaV2` with the new ones and a stage to `OmbreMigrationPlan`.
enum OmbreSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [TabContainer.self, Tab.self, Folder.self, SpaceTask.self, History.self, Download.self]
    }
}

/// How the main database moves from one schema to the next (none yet).
enum OmbreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OmbreSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
