import Foundation
import SwiftData

struct SuggestionType: Domain {
    typealias M = SuggestionTypeModel
    typealias P = SuggestionTypePersistentModel
    
    struct SuggestionTypeModel: Model {
        var uuid: UID
        let suggestionType: String
        let suggestionName: String
    }
    
    let identifier: ModelIdentifier?
    var model: SuggestionType.SuggestionTypeModel
    
    init(model: SuggestionTypeModel) {
        self.model = model
        self.identifier = nil
    }
    
    init(model: SuggestionTypeModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }
    
    // MARK: - Mapping Methods
    
    func toPersistentModel(context: ModelContext?) -> SuggestionTypePersistentModel {
        let persistent = SuggestionTypePersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.suggestionType = model.suggestionType.encrypt
        persistent.suggestionName = model.suggestionName.encrypt
        return persistent
    }
    
    static func fromPersistentModel(_ persistent: SuggestionTypePersistentModel) -> SuggestionType {
        let model = SuggestionTypeModel(
            uuid: persistent.uuid.decrypt,
            suggestionType: persistent.suggestionType.decrypt,
            suggestionName: persistent.suggestionName.decrypt
        )
        return SuggestionType(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

struct SuggestionTypeAPIResponse: APIResponse {
    let suggestionType: String
    let suggestionName: String
    
    enum CodingKeys: String, CodingKey {
        case suggestionType = "type"
        case suggestionName = "name"
    }
        
    func toDomain() -> SuggestionType {
        let model = SuggestionType.SuggestionTypeModel(
            uuid: suggestionType,
            suggestionType: suggestionType,
            suggestionName: suggestionName
        )
        return SuggestionType(model: model)
    }
}

// MARK: - Persistent Model

@Model
final class SuggestionTypePersistentModel: UpdatablePersistentModel {
    var pk: String?
    var ik: String?
    var uuid: String = ""
    var suggestionType: String = ""
    var suggestionName: String = ""
    
    init() {}
    
    func updateProperties(from suggestion: SuggestionTypePersistentModel) {
        self.uuid = suggestion.uuid
        self.suggestionType = suggestion.suggestionType
        self.suggestionName = suggestion.suggestionName
    }
}
