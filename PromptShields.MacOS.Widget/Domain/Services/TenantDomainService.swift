import SwiftData
import SwiftUI
import Foundation
import os

enum TenantServiceError: Error {
    case missingTenant
    case missingCurrentUserId
    case invalidTenantFormat
    case networkError(Error)
}

extension EnvironmentValues {
    var teanantDomainService: TenantDomainServiceImpl {
        get { self[TenantDomainServiceKey.self] }
        set { self[TenantDomainServiceKey.self] = newValue }
    }
}

struct TenantDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return TenantDomainServiceImpl()
    }()
}

protocol TenantDomainService: Sendable {
    var currentTenant: Tenant { get async throws }
    func currentTenant(refresh: Bool) async throws -> Tenant
}

struct TenantDomainServiceImpl: TenantDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var tenantNetworkService: TenantNetworkService
    @Inject
    private var profileDomainService: ProfileDomainService
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: TenantDomainService.self)
    )
    
    var currentTenant: Tenant {
        get async throws {
            try await currentTenant(refresh: false)
        }
    }
    
    func currentTenant(refresh: Bool) async throws -> Tenant {
        let fetchRemote: () async throws -> Tenant = {
            try await getTenant(
                tenantId: try await
                profileDomainService
                    .currentProfile(refresh: refresh)
                        .model
                            .defaultTenantId)
        }
        if refresh {
            return try await persistenceManager.syncLocalWithRemote(domain: fetchRemote())
        } else {
            let currentProfile = try await profileDomainService.currentProfile
            do {
                return try await persistenceManager.fetchItem(filter: { $0.model.uuid == currentProfile.model.defaultTenantId })
            } catch PersistenceManagerError.missingModel {
                return try await persistenceManager.syncLocalWithRemote(domain: fetchRemote())
            } catch {
                throw error
            }
        }
    }
    
    private func getTenant(tenantId: String) async throws -> Tenant {
        let result = try await tenantNetworkService.read(tenantId: tenantId)
        let domain = result.toDomain()
        try await persistenceManager.update(domain: result.toDomain())
        return domain
    }
}
