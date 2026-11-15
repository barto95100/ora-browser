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

/// The second schema: tab groups (`TabGroup`), a model of their own. The
/// other models are unchanged, so V1 can keep listing the current classes.
enum OmbreSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        OmbreSchemaV1.models + [TabGroup.self]
    }
}

/// How the main database moves from one schema to the next.
enum OmbreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OmbreSchemaV1.self, OmbreSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        // A new model only: SwiftData adds its table.
        [.lightweight(fromVersion: OmbreSchemaV1.self, toVersion: OmbreSchemaV2.self)]
    }
}
