import Foundation

protocol SuggestionNetworkService: NetworkService {
    func process(text: String, llmProvider: String, suggestionGroupId: String, suggestionType: String, application: String) async throws -> SuggestionAPIResponse
    func list(suggestionGroupId: String, llmProvider: String, teamId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SuggestionAPIResponse>
    func fetchSuggestionTypes() async throws -> ListResponse<SuggestionTypeAPIResponse>
}

struct SuggestionNetworkServiceImpl: SuggestionNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager
    
    private let path = "suggestion"
    
    func process(text: String,
                 llmProvider: String,
                 suggestionGroupId: String,
                 suggestionType: String,
                 application: String) async throws -> SuggestionAPIResponse {
        let payload = SuggestionRequest(body: text,
                                        suggestionGroupId: suggestionGroupId,
                                        suggestionType: suggestionType,
                                        llmProvider: llmProvider,
                                        application: application)
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(path)/process/",
            method: .POST,
            body: payload,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func list(suggestionGroupId: String, llmProvider: String, teamId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SuggestionAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(path)/\(teamId)/\(suggestionGroupId)",
            method: .GET,
            queryParameters: ["offset": "\(offset)", "limit": "\(limit)"],
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func fetchSuggestionTypes() async throws -> ListResponse<SuggestionTypeAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(path)/types",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
}
