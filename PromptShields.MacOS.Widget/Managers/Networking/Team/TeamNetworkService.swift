import Foundation
protocol TeamNetworkService: NetworkService {
    func read(subscriptionId: String, teamId: String) async throws -> TeamAPIResponse
}

struct TeamNetworkServiceImpl: TeamNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager
    private let path = "teams"

    func read(subscriptionId: String, teamId: String) async throws -> TeamAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/subscriptions/\(subscriptionId)/\(path)/\(teamId)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
}
