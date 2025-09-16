import Foundation

// Remove duplicate TenantAPIResponse definition. Use the one from the domain model.

protocol TenantNetworkService: Sendable {
    func read(tenantId: String) async throws -> TenantAPIResponse
}

struct TenantNetworkServiceImpl: TenantNetworkService {
    let networkManager: NetworkManager
    let keychainManager: KeychainManager
    
    func read(tenantId: String) async throws -> TenantAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/tenants/\(tenantId)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
}
