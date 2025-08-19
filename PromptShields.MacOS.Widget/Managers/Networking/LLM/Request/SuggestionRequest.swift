import Foundation

struct SuggestionRequest: SendableEncodable {
    let body: String
    let suggestionType: String
    let llmProvider: String
    let application: String
    
    enum CodingKeys: String, CodingKey {
        case body
        case suggestionType = "suggestion_type"
        case llmProvider = "llm_provider"
        case application
    }
}
