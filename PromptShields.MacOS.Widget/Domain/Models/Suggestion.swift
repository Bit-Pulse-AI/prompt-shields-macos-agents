import Foundation
import SwiftData

// MARK: - Suggestion Type
enum SuggestionType: String, CaseIterable, Codable {
    case grammar = "grammar"
    case spelling = "spelling"
    case style = "style"
    case clarity = "clarity"
    case tone = "tone"
}

struct Suggestion: Domain {
    typealias M = SuggestionModel
    typealias P = SuggestionPersistentModel
    typealias R = SuggestionAPIResponse
    
    struct SuggestionModel: Model {
        let uuid: UID
        let text: String
        let suggestion: String
        let type: SuggestionType
        let offset: Int
        let length: Int
        let confidence: Double
        let explanation: String
        let timestamp: Date
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
        persistent.uuid = model.uuid
        persistent.text = model.text
        persistent.suggestion = model.suggestion
        persistent.type = model.type.rawValue
        persistent.offset = model.offset
        persistent.length = model.length
        persistent.confidence = model.confidence
        persistent.explanation = model.explanation
        persistent.timestamp = model.timestamp
        return persistent
    }
    
    static func fromPersistentModel(_ persistent: SuggestionPersistentModel) -> Suggestion {
        let model = SuggestionModel(
            uuid: persistent.uuid,
            text: persistent.text,
            suggestion: persistent.suggestion,
            type: SuggestionType(rawValue: persistent.type) ?? .grammar,
            offset: persistent.offset,
            length: persistent.length,
            confidence: persistent.confidence,
            explanation: persistent.explanation,
            timestamp: persistent.timestamp
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
    let id: String
    let title: String
    let authorId: String
    let memberIds: [String]
    let messageCount: Int
    let channelStatus: String
    let projectId: String
    let publicKey: String?
    let llmProvider: String?
    let llmKey: String?
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case authorId = "author"
        case memberIds = "member_ids"
        case messageCount = "message_count"
        case channelStatus = "channel_status"
        case projectId = "project_id"
        case publicKey = "public_key"
        case llmProvider = "llm_provider"
        case llmKey = "llm_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    func toDomain() -> Suggestion {
        let dateFormatter = ISO8601DateFormatter()
        let model = Suggestion.SuggestionModel(uuid: "",
                                               text: "",
                                               suggestion: "",
                                               type: .clarity,
                                               offset: 0,
                                               length: 0,
                                               confidence: 0,
                                               explanation: "n/a",
                                               timestamp: Date())
        return Suggestion(model: model)
    }
}

// MARK: - Persistent Model

@Model
final class SuggestionPersistentModel: UpdatablePersistentModel {
    var pk: String?
    
    var ik: String?
    
    var uuid: String = ""
    var text: String = ""
    var suggestion: String = ""
    var type: String = ""
    var offset: Int = 0
    var length: Int = 0
    var confidence: Double = 0.0
    var explanation: String = ""
    var timestamp: Date = Date()
    
    init() {}
    
    func updateProperties(from suggestion: SuggestionPersistentModel) {
        self.uuid = suggestion.uuid
        self.text = suggestion.text
        self.suggestion = suggestion.suggestion
        self.type = suggestion.type
        self.offset = suggestion.offset
        self.length = suggestion.length
        self.confidence = suggestion.confidence
        self.explanation = suggestion.explanation
        self.timestamp = suggestion.timestamp
    }
}
