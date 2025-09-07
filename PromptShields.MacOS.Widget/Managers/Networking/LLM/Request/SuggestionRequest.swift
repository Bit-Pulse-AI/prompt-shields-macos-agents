import Foundation

struct SuggestionRequest: SendableEncodable {
    let body: String
    let suggestionGroupId: String
    let suggestionType: String
    let llmProvider: String
    let application: String
    
    enum CodingKeys: String, CodingKey {
        case body
        case suggestionGroupId = "suggestion_group_id"
        case suggestionType = "suggestion_type"
        case llmProvider = "llm_provider"
        case application
    }
}
