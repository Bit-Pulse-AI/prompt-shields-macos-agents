import Foundation
import SwiftData

final class PersistenceStack: Sendable {
    let modelContainer: ModelContainer

    init(modelTypes: [any PersistentModel.Type], migrationPlan: any SchemaMigrationPlan.Type) {
        do {
            let schema = Schema(modelTypes)
            guard let url = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("PromptshieldsDB.sqlite") else {
                fatalError("failed sqlite")
            }
            let modelConfiguration = ModelConfiguration(
                url: url)

            do {
                modelContainer = try ModelContainer(for: schema,
                                                    migrationPlan: migrationPlan,
                                                    configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }
}
