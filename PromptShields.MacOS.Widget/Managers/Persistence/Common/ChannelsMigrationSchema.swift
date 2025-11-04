import SwiftData

enum ChannelsMigrationPlan: SchemaMigrationPlan {
    static var stages: [MigrationStage] {
        []
    }

    static var schemas: [any VersionedSchema.Type] {
        [ChannelsSchemaV1.self]
    }
}
