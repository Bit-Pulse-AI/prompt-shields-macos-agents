import Foundation
protocol OrganisationNetworkService: NetworkService {
    func create(tenantId: String, name: String, description: String?) async throws -> OrganisationAPIResponse
    func read(tenantId: String, organisationId: String) async throws -> OrganisationAPIResponse
    func update(tenantId: String, organisationId: String, name: String?, description: String?) async throws -> OrganisationAPIResponse
    func delete(tenantId: String, organisationId: String) async throws
    func list(tenantId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<OrganisationAPIResponse>
    func list(tenantId: String) async throws -> PaginatedResponse<OrganisationAPIResponse>
}

struct OrganisationNetworkServiceImpl: OrganisationNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager
    
    private let path = "organisations"
    
    func create(tenantId: String, name: String, description: String? = nil) async throws -> OrganisationAPIResponse {
        let payload = CreateOrganisationRequest(name: name, description: description)
        let request = try RequestBuilder().request(
            url: "\(baseURL)/tenants/\(tenantId)/\(path)",
            method: .POST,
            body: payload,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func read(tenantId: String, organisationId: String) async throws -> OrganisationAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/tenants/\(tenantId)/\(path)/\(organisationId)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func update(tenantId: String, organisationId: String, name: String? = nil, description: String? = nil) async throws -> OrganisationAPIResponse {
        let payload = UpdateOrganisationRequest(name: name, description: description)
        let request = try RequestBuilder().request(
            url: "\(baseURL)/tenants/\(tenantId)/\(path)/\(organisationId)/",
            method: .PUT,
            body: payload,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
    
    func delete(tenantId: String, organisationId: String) async throws {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/tenants/\(tenantId)/\(path)/\(organisationId)/",
            method: .DELETE,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        try await networkManager.performWithAutoRefresh(request: request)
    }
    
    func list(tenantId: String) async throws -> PaginatedResponse<OrganisationAPIResponse> {
        try await list(tenantId: tenantId, offset: 1, limit: 20)
    }
    
    func list(tenantId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<OrganisationAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/tenants/\(tenantId)/\(path)?offset=\(offset)&limit=\(limit)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
} 
