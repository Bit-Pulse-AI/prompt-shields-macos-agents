import Foundation
import SwiftData

struct Suggestion: Domain {
    typealias M = SuggestionModel
    typealias P = SuggestionPersistentModel
    typealias R = SuggestionAPIResponse
    
    struct SuggestionModel: Model {
        var uuid: UID
        let originalText: String
        let suggestedText: String
        let suggestionType: SuggestionType?
        let application: String
        let createdAt: Date
    }
    
    let identifier: ModelIdentifier?
    var model: Suggestion.SuggestionModel
    
    init(model: SuggestionModel) {
        self.model = model
        self.identifier = nil
    }
    
    init(model: SuggestionModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }
    
    // MARK: - Mapping Methods
    
    func toPersistentModel(context: ModelContext?) -> SuggestionPersistentModel {
        let persistent = SuggestionPersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.originalText = model.originalText.encrypt
        persistent.suggestedText = model.suggestedText.encrypt
        persistent.suggestionType = model.suggestionType?.rawValue.encrypt
        persistent.application = model.application.encrypt
        persistent.createdAt = model.createdAt
        return persistent
    }
    
    static func fromPersistentModel(_ persistent: SuggestionPersistentModel) -> Suggestion {
        let model = SuggestionModel(
            uuid: persistent.uuid.decrypt,
            originalText: persistent.originalText.decrypt,
            suggestedText: persistent.suggestedText.decrypt,
            suggestionType: SuggestionType(rawValue: persistent.suggestionType?.decrypt ?? ""),
            application: persistent.application.decrypt,
            createdAt: persistent.createdAt
        )
        return Suggestion(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
    
    static func fromAPIResponse(_ response: Data) throws -> Suggestion {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let channelDTO = try decoder.decode(SuggestionAPIResponse.self, from: response)
        return channelDTO.toDomain()
    }
}

// MARK: - API Models

struct SuggestionAPIResponse: APIResponse {
    let uuid: String?
    let originalText: String
    let suggestedText: String
    let suggestionType: String
    let application: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case uuid = "id"
        case originalText = "original_text"
        case suggestedText = "suggested_text"
        case suggestionType = "suggestion_type"
        case application
        case createdAt = "created_at"
    }
    
    func toDomain() -> Suggestion {
        let model = Suggestion.SuggestionModel(uuid: uuid ?? UUID().uuidString,
                                               originalText: originalText,
                                               suggestedText: suggestedText,
                                               suggestionType: SuggestionType(rawValue: suggestionType),
                                               application: application,
                                               createdAt: Date())
        return Suggestion(model: model)
    }
}

// MARK: - Persistent Model

@Model
final class SuggestionPersistentModel: UpdatablePersistentModel {
    var pk: String?
    var ik: String?
    var uuid: String = ""
    var originalText: String = ""
    var suggestedText: String = ""
    var suggestionType: String?
    var application: String = ""
    var createdAt: Date = Date()
    
    init() {}
    
    func updateProperties(from suggestion: SuggestionPersistentModel) {
        self.uuid = suggestion.uuid
        self.originalText = suggestion.originalText
        self.suggestedText = suggestion.suggestedText
        self.suggestionType = suggestion.suggestionType
        self.application = suggestion.application
        self.createdAt = suggestion.createdAt
    }
}
