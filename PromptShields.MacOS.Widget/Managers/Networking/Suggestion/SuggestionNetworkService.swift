import Foundation

protocol SuggestionNetworkService: NetworkService {
    func analyze(text: String, llmProvider: String, suggestionGroupId: String, teamId: String, suggestionType: String, application: String) async throws -> SuggestionAPIResponse
    func list(suggestionGroupId: String, llmProvider: String, teamId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SuggestionAPIResponse>
    func fetchSuggestionTypes() async throws -> ListResponse<SuggestionTypeAPIResponse>
    func fetchSuggestionGroup(suggestionGroupId: String, teamId: String) async throws -> SuggestionGroupAPIResponse
}

struct SuggestionNetworkServiceImpl: SuggestionNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager
    
    private let suggestionPath = "suggestion"
    private let suggestionGroupPath = "suggestion_group"
    
    func analyze(text: String,
                 llmProvider: String,
                 suggestionGroupId: String,
                 teamId: String,
                 suggestionType: String,
                 application: String) async throws -> SuggestionAPIResponse {
        let payload = SuggestionRequest(body: text,
                                        suggestionGroupId: suggestionGroupId,
                                        suggestionType: suggestionType,
                                        llmProvider: llmProvider,
                                        teamId: teamId,
                                        application: application)
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionPath)/analyze/",
            method: .POST,
            body: payload,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func fetchSuggestionTypes() async throws -> ListResponse<SuggestionTypeAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionPath)/types",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func list(suggestionGroupId: String, llmProvider: String, teamId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SuggestionAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/teams/\(teamId)/suggestion_group/\(suggestionGroupId)/suggestions",
            method: .GET,
            queryParameters: ["offset": "\(offset)", "limit": "\(limit)"],
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func fetchSuggestionGroup(suggestionGroupId: String, teamId: String) async throws -> SuggestionGroupAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/teams/\(teamId)/suggestion_group/\(suggestionGroupId)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
}
