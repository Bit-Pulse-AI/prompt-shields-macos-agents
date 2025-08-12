import Foundation

protocol SubscriptionNetworkService: NetworkService {
    func read(organisationId: String, subscriptionId: String) async throws -> SubscriptionAPIResponse
    func list(organisationId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SubscriptionAPIResponse>
    func list(organisationId: String) async throws -> PaginatedResponse<SubscriptionAPIResponse>
}
struct SubscriptionNetworkServiceImpl: SubscriptionNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager
    
    private let path = "subscriptions"

    func read(organisationId: String, subscriptionId: String) async throws -> SubscriptionAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/organisations/\(organisationId)/\(path)/\(subscriptionId)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.perform(request: request).decode()
    }
    
    func list(organisationId: String) async throws -> PaginatedResponse<SubscriptionAPIResponse> {
        try await list(organisationId: organisationId, offset: 0, limit: 20)
    }
    
    func list(organisationId: String, offset: Int = 0, limit: Int = 20) async throws -> PaginatedResponse<SubscriptionAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/organisations/\(organisationId)/\(path)?offset=\(offset)&limit=\(limit)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.perform(request: request).decode()
    }
} 
