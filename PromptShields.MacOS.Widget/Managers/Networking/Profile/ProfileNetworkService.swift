import Foundation
protocol ProfileNetworkService: NetworkService {
    func getProfile() async throws -> ProfileAPIResponse
}

struct ProfileNetworkServiceImpl: ProfileNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager
    
    private let path = "profiles"
    
    func getProfile() async throws -> ProfileAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(path)/",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
}
