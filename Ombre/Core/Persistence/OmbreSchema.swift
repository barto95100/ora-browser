import Foundation
import SwiftData

/// The main database's first schema. Every model is listed, including those
/// only reached through relationships.
///
/// Its models are frozen copies (`OmbreSchemaV1Models.swift`): SwiftData
/// recognizes a database's version by them. Before changing a model (a
/// property added, renamed or retyped), freeze its current form in the last
/// version, add a version with the new classes and a stage to
/// `OmbreMigrationPlan`, and check it with `OmbreMigrationTests` (one real
/// database of each earlier version among its fixtures). A database opened by
/// a version it doesn't know is moved aside (`DatabaseRecovery`): an older
/// build can't open a newer one.
enum OmbreSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            OmbreSchemaV1.TabContainer.self,
            OmbreSchemaV1.Tab.self,
            OmbreSchemaV1.Folder.self,
            OmbreSchemaV1.SpaceTask.self,
            OmbreSchemaV1.History.self,
            Download.self
        ]
    }
}

/// The second schema: tab groups (`TabGroup`), a model of their own. The
/// other models are V1's.
enum OmbreSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        OmbreSchemaV1.models + [TabGroup.self]
    }
}

/// The third schema: a tab's own name (`Tab.customName`, see `TabName`).
/// The current classes.
enum OmbreSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [TabContainer.self, Tab.self, Folder.self, SpaceTask.self, History.self, Download.self, TabGroup.self]
    }
}

/// How the main database moves from one schema to the next.
enum OmbreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OmbreSchemaV1.self, OmbreSchemaV2.self, OmbreSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            // A new model only: SwiftData adds its table.
            .lightweight(fromVersion: OmbreSchemaV1.self, toVersion: OmbreSchemaV2.self),
            // An optional property: SwiftData adds its column, empty.
            .lightweight(fromVersion: OmbreSchemaV2.self, toVersion: OmbreSchemaV3.self)
        ]
    }
}
