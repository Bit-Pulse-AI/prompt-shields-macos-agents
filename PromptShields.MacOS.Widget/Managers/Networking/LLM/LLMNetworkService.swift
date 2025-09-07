import Foundation
protocol LLMNetworkService: NetworkService {
    func getAvailableLLMs() async throws -> ListResponse<LLMAPIResponse>
}

struct LLMNetworkServiceImpl: LLMNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager
    
    private let path = "llm"
    
    func getAvailableLLMs() async throws -> ListResponse<LLMAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(path)/",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.perform(request: request).decode()
    }
}
