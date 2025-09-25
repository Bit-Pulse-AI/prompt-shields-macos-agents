import Foundation
import SwiftData

enum ChannelsSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static let models: [any PersistentModel.Type] =
        [SuggestionTypePersistentModel.self,
         SuggestionGroupPersistentModel.self,
         SuggestionPersistentModel.self,
         OrganisationPersistentModel.self,
         SubscriptionPersistentModel.self,
         TeamPersistentModel.self,
         TenantPersistentModel.self,
         UserPreferencesPersistentModel.self,
         UserPersistentModel.self]
}
