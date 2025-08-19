import Foundation
protocol LLMNetworkService: NetworkService {
    func process(text: String, llmProvider: String, suggestionType: String, application: String) async throws -> SuggestionAPIResponse
}

struct LLMNetworkServiceImpl: LLMNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager
    
    private let path = "llm"
    
    func process(text: String, llmProvider: String, suggestionType: String, application: String) async throws -> SuggestionAPIResponse {
        let payload = SuggestionRequest(body: text, suggestionType: suggestionType, llmProvider: llmProvider, application: application)
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(path)/suggestions/",
            method: .POST,
            body: payload,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.perform(request: request).decode()
    }
}
