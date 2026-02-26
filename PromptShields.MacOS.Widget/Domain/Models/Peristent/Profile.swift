import Foundation
import SwiftData

struct Profile: Domain {
    typealias M = ProfileModel
    typealias P = ProfilePersistentModel

    struct ProfileModel: Model {
        let uuid: UID
        var acceptedTerms: String?
        var acceptedTermsDate: Date?
        let userId: String
        let defaultTenantId: UID
        let defaultOrganisationId: UID
        let defaultSubscriptionId: UID
        let defaultSuggestionGroupId: UID
        let defaultTeamId: UID
    }

    let identifier: ModelIdentifier?
    var model: Profile.ProfileModel

    init(model: ProfileModel) {
        self.model = model
        self.identifier = nil
    }

    init(model: ProfileModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }

    // MARK: - Mapping Methods

    func toPersistentModel(context: ModelContext?) -> ProfilePersistentModel {
        let persistent = ProfilePersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.defaultTenantId = model.defaultTenantId.encrypt
        persistent.defaultOrganisationId = model.defaultOrganisationId.encrypt
        persistent.defaultSubscriptionId = model.defaultSubscriptionId.encrypt
        persistent.defaultSuggestionGroupId = model.defaultSuggestionGroupId.encrypt
        persistent.defaultTeamId = model.defaultTeamId.encrypt
        persistent.acceptedTerms = model.acceptedTerms?.encrypt
        persistent.acceptedTermsDate = model.acceptedTermsDate
        return persistent
    }

    static func fromPersistentModel(_ persistent: ProfilePersistentModel) -> Profile {
        let model = ProfileModel(
            uuid: persistent.uuid.decrypt, acceptedTerms: persistent.acceptedTerms,
            acceptedTermsDate: persistent.acceptedTermsDate,
            userId: persistent.userId.decrypt,
            defaultTenantId: persistent.defaultTenantId.decrypt,
            defaultOrganisationId: persistent.defaultOrganisationId.decrypt,
            defaultSubscriptionId: persistent.defaultSubscriptionId.decrypt,
            defaultSuggestionGroupId: persistent.defaultSuggestionGroupId.decrypt,
            defaultTeamId: persistent.defaultTeamId.decrypt
        )
        return Profile(model: model,
                       identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

// MARK: - API Models

struct ProfileAPIResponse: APIResponse {
    let id: UID
    let defaultTenantId: UID
    let defaultOrganisationId: UID
    let defaultSubscriptionId: UID
    let defaultSuggestionGroupId: UID
    let defaultTeamId: UID
    let userId: String
    let acceptedTerms: String?
    let acceptedTermsDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case defaultTenantId = "default_tenant_id"
        case defaultOrganisationId = "default_organisation_id"
        case defaultSubscriptionId = "default_subscription_id"
        case defaultSuggestionGroupId = "default_suggestion_group_id"
        case defaultTeamId = "default_team_id"
        case acceptedTerms = "accepted_terms"
        case acceptedTermsDate = "accepted_date"
    }

    func toDomain() -> Profile {
        let dateFormatter = ISO8601DateFormatter()
        var acceptedTermsDate: Date?
        if let safe_acceptedTermsDate = self.acceptedTermsDate {
            acceptedTermsDate = dateFormatter.date(from: safe_acceptedTermsDate)
        }
        let model = Profile.ProfileModel(
            uuid: id,
            acceptedTerms: acceptedTerms,
            acceptedTermsDate: acceptedTermsDate,
            userId: userId,
            defaultTenantId: defaultTenantId,
            defaultOrganisationId: defaultOrganisationId,
            defaultSubscriptionId: defaultSubscriptionId,
            defaultSuggestionGroupId: defaultSuggestionGroupId,
            defaultTeamId: defaultTeamId
        )
        return Profile(model: model)
    }
}

// MARK: - Persistent Model

@Model
final class ProfilePersistentModel: UpdatablePersistentModel {
    var uuid: UID = ""
    var pk: String?
    var ik: String?
    var userId: UID = ""
    var defaultTenantId: UID = ""
    var defaultOrganisationId: UID = ""
    var defaultSubscriptionId: UID = ""
    var defaultSuggestionGroupId: UID = ""
    var defaultTeamId: UID = ""
    var acceptedTerms: String?
    var acceptedTermsDate: Date?

    init() {}

    func updateProperties(from other: ProfilePersistentModel) {
        self.uuid = other.uuid
        self.userId = other.userId
        self.defaultTenantId = other.defaultTenantId
        self.defaultOrganisationId = other.defaultOrganisationId
        self.defaultSubscriptionId = other.defaultSubscriptionId
        self.defaultSuggestionGroupId = other.defaultSuggestionGroupId
        self.defaultTeamId = other.defaultTeamId
        self.acceptedTerms = other.acceptedTerms
        self.acceptedTermsDate = other.acceptedTermsDate
    }
}
