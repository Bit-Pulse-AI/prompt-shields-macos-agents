import Foundation
protocol TeamNetworkService: NetworkService {
    func create(subscriptionId: String, name: String) async throws -> TeamAPIResponse
    func read(subscriptionId: String, teamId: String) async throws -> TeamAPIResponse
    func update(subscriptionId: String, teamId: String, name: String?, teamStatus: TeamStatus?) async throws -> TeamAPIResponse
    func delete(subscriptionId: String, teamId: String) async throws
    func list(subscriptionId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<TeamAPIResponse>
    func list(subscriptionId: String) async throws -> PaginatedResponse<TeamAPIResponse>
}
struct TeamNetworkServiceImpl: TeamNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager
    private let path = "teams"
    
    func create(subscriptionId: String, name: String) async throws -> TeamAPIResponse {
        let payload = CreateTeamRequest(name: name)
        let request = try RequestBuilder().request(
            url: "\(baseURL)/subscriptions/\(subscriptionId)/\(path)",
            method: .POST,
            body: payload,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func read(subscriptionId: String, teamId: String) async throws -> TeamAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/subscriptions/\(subscriptionId)/\(path)/\(teamId)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func update(subscriptionId: String, teamId: String, name: String? = nil, teamStatus: TeamStatus? = nil) async throws -> TeamAPIResponse {
        let teamStatusRequest = teamStatus.map { status in
            switch status {
            case .active:
                return TeamStatusRequest.active
            case .archived:
                return TeamStatusRequest.archived
            case .deleted:
                return TeamStatusRequest.archived // Map deleted to archived for API
            }
        }
        
        let payload = UpdateTeamRequest(name: name, teamStatus: teamStatusRequest)
        let request = try RequestBuilder().request(
            url: "\(baseURL)/subscriptions/\(subscriptionId)/\(path)/\(teamId)",
            method: .PUT,
            body: payload,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func delete(subscriptionId: String, teamId: String) async throws {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/subscriptions/\(subscriptionId)/\(path)/\(teamId)",
            method: .DELETE,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        try await networkManager.performWithAutoRefresh(request: request)
    }
    
    func list(subscriptionId: String) async throws -> PaginatedResponse<TeamAPIResponse> {
        try await list(subscriptionId: subscriptionId, offset: 0, limit: 10)
    }
    
    func list(subscriptionId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<TeamAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/subscriptions/\(subscriptionId)/\(path)?offset=\(offset)&limit=\(limit)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
} 
