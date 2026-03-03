import Foundation
import SwiftData

struct SuggestionTypeGroup: Domain {
    typealias M = SuggestionTypeGroupModel
    typealias P = SuggestionTypeGroupPersistentModel

    struct SuggestionTypeGroupModel: Model {
        let uuid: UID
        let title: String
        let description: String
        let teamId: String
        let suggestionCount: Int
        let createdAt: Date
    }

    let identifier: ModelIdentifier?
    var model: SuggestionTypeGroup.SuggestionTypeGroupModel

    init(model: SuggestionTypeGroupModel) {
        self.model = model
        self.identifier = nil
    }

    init(model: SuggestionTypeGroupModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }

    // MARK: - Mapping Methods

    func toPersistentModel(context: ModelContext?) -> SuggestionTypeGroupPersistentModel {
        let persistent = SuggestionTypeGroupPersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.title = model.title.encrypt
        persistent.suggestionDescription = model.description.encrypt
        persistent.teamId = model.teamId.encrypt
        persistent.suggestionCount = model.suggestionCount
        persistent.createdAt = model.createdAt
        return persistent
    }

    static func fromPersistentModel(_ persistent: SuggestionTypeGroupPersistentModel) -> SuggestionTypeGroup {
        let model = SuggestionTypeGroupModel(
            uuid: persistent.uuid.decrypt,
            title: persistent.title.decrypt,
            description: persistent.suggestionDescription.decrypt,
            teamId: persistent.teamId.decrypt,
            suggestionCount: persistent.suggestionCount,
            createdAt: persistent.createdAt
        )
        return SuggestionTypeGroup(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

struct SuggestionTypeGroupAPIResponse: APIResponse {
    let uuid: String?
    let title: String
    let description: String
    let teamId: String
    let suggestionCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case uuid = "id"
        case title = "title"
        case description = "description"
        case teamId = "team_id"
        case suggestionCount = "suggestion_count"
        case createdAt = "created_at"
    }

    func toDomain() -> SuggestionTypeGroup {
        let model = SuggestionTypeGroup.SuggestionTypeGroupModel(uuid: uuid ?? UUID().uuidString,
                                                         title: title,
                                                         description: description,
                                                         teamId: teamId,
                                                         suggestionCount: suggestionCount,
                                                         createdAt: createdAt)
        return SuggestionTypeGroup(model: model)
    }
}

// MARK: - Persistent Model

@Model
final class SuggestionTypeGroupPersistentModel: UpdatablePersistentModel {
    var pk: String?
    var ik: String?
    var uuid: String = ""
    var title: String = ""
    var suggestionDescription: String = ""
    var teamId: String = ""
    var suggestionCount: Int = 0
    var createdAt: Date = Date()

    init() {}

    func updateProperties(from suggestion: SuggestionTypeGroupPersistentModel) {
        self.uuid = suggestion.uuid
        self.title = suggestion.title
        self.suggestionDescription = suggestion.suggestionDescription
        self.teamId = suggestion.teamId
        self.suggestionCount = suggestion.suggestionCount
        self.createdAt = suggestion.createdAt
    }
}
