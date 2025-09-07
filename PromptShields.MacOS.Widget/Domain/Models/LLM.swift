import Foundation
import SwiftData

struct LLM: Domain {
    typealias M = LLMModel
    typealias P = LLMPersistentModel
    
    struct LLMModel: Model {
        var uuid: UID
        var name: String
        var type: String
    }
    
    let identifier: ModelIdentifier?
    var model: LLM.LLMModel
    
    init(model: LLMModel) {
        self.model = model
        self.identifier = nil
    }
    
    init(model: LLMModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }
    
    // MARK: - Mapping Methods
    
    func toPersistentModel(context: ModelContext?) -> LLMPersistentModel {
        let persistent = LLMPersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.name = model.name.encrypt
        persistent.type = model.type.encrypt
        return persistent
    }
    
    static func fromPersistentModel(_ persistent: LLMPersistentModel) -> LLM {
        let model = LLMModel(
            uuid: persistent.uuid.decrypt,
            name: persistent.name.decrypt,
            type: persistent.type.decrypt
        )
        return LLM(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

// MARK: - API Models
struct LLMAPIResponse: APIResponse {
    let type: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case name
    }
    
    func toDomain() -> LLM {
        let model = LLM.LLMModel(
            uuid: type,
            name: name,
            type: type
        )
        return LLM(model: model)
    }
}

// MARK: - Persistent Model

@Model
final class LLMPersistentModel: UpdatablePersistentModel {
    var uuid: String = ""
    var pk: String?
    var ik: String?
    var name: String = ""
    var type: String = ""
    
    init() {
        // Default initializer for SwiftData
    }
    
    func updateProperties(from other: LLMPersistentModel) {
        self.uuid = other.uuid
        self.name = other.name
        self.type = other.type
    }
}

extension LLM {
    var encrypt: LLM {
        let model = LLMModel(uuid: model.uuid.encrypt,
                                      name: model.name.encrypt,
                                      type: model.type.encrypt)
        return LLM(model: model,
                            identifier: identifier)
    }
}
