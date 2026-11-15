import Foundation
import SwiftData

/// The main database's first schema. Every model is listed, including those
/// only reached through relationships.
///
/// V1 (and V2) list the app's current classes: the models of V1 must never
/// change. Before changing one (a property added, renamed or retyped), freeze
/// copies of V1's classes inside this enum, add a version with the new ones
/// and a stage to `OmbreMigrationPlan`, and check it with
/// `OmbreMigrationTests` (its V1 database comes from a build before groups).
/// A database opened by a version it doesn't know is moved aside
/// (`DatabaseRecovery`): an older build can't open a V2 one.
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
