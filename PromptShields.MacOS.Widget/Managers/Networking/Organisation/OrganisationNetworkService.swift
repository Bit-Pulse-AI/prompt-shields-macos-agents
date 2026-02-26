import Foundation
protocol OrganisationNetworkService: NetworkService {
    func read(tenantId: String, organisationId: String) async throws -> OrganisationAPIResponse
}

struct OrganisationNetworkServiceImpl: OrganisationNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager

    private let path = "organisations"

    func read(tenantId: String, organisationId: String) async throws -> OrganisationAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/tenants/\(tenantId)/\(path)/\(organisationId)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
}
