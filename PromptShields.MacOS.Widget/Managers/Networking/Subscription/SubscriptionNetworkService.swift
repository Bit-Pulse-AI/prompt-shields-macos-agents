import Foundation

protocol SubscriptionNetworkService: NetworkService {
    func read(organisationId: String, subscriptionId: String) async throws -> SubscriptionAPIResponse
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
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
}
