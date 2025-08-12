import SwiftData
import SwiftUI
import Foundation
import os

enum OrganisationServiceError: Error {
    case missingOrganisation
    case missingTenant
    case missingCurrentUserId
    case invalidOrganisationFormat
    case networkError(Error)
}

extension EnvironmentValues {
    var organisationDomainService: OrganisationDomainServiceImpl {
        get { self[OrganisationDomainServiceKey.self] }
        set { self[OrganisationDomainServiceKey.self] = newValue }
    }
}

struct OrganisationDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return OrganisationDomainServiceImpl()
    }()
}

protocol OrganisationDomainService: Sendable {
    var currentOrganisation: Organisation { get async throws }
    func currentOrganisation(refresh: Bool) async throws -> Organisation
    
    func createOrganisation(tenant: Tenant,
                            name: String,
                            description: String?) async throws -> Organisation
    
    func getOrganisations(tenant: Tenant) async throws -> [Organisation]
    
    func updateOrganisation(organisation: Organisation,
                            tenant: Tenant,
                            name: String,
                            description: String?,
                            localData: @Sendable @escaping (Organisation) -> Void,
                            remoteData: @Sendable @escaping (Result<Organisation, Error>) -> Void)
    
    func deleteOrganisation(organisation: Organisation,
                            tenant: Tenant,
                            localData: @Sendable @escaping () -> Void,
                            remoteData: @Sendable @escaping (Result<Void, Error>) -> Void)
}

struct OrganisationDomainServiceImpl: OrganisationDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var organisationNetworkService: OrganisationNetworkService
    @Inject
    private var tenantDomainService: TenantDomainService
    @Inject
    private var profileDomainService: ProfileDomainService
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: OrganisationDomainService.self)
    )
    var currentOrganisation: Organisation {
        get async throws {
            try await currentOrganisation(refresh: false)
        }
    }
    
    func currentOrganisation(refresh: Bool) async throws -> Organisation {
        let fetchRemote: () async throws -> Organisation = {
            let currentProfile = try await profileDomainService.currentProfile
            return try await getOrganisation(
                tenantId: currentProfile.model.defaultTenantId,
                organisationId: currentProfile.model.defaultOrganisationId)
        }
        if refresh {
            return try await persistenceManager.syncLocalWithRemote(domain: fetchRemote())
        } else {
            let currentProfile = try await profileDomainService.currentProfile
            do {
                return try await persistenceManager.fetchItem(filter: { $0.model.uuid == currentProfile.model.defaultOrganisationId })
            } catch PersistenceManagerError.missingModel {
                return try await persistenceManager.syncLocalWithRemote(domain: fetchRemote())
            } catch {
                throw error
            }
        }
    }
    
    func createOrganisation(tenant: Tenant,
                            name: String,
                            description: String?) async throws -> Organisation {
        do {
            // Create organisation locally first
            let organisationModel = Organisation.OrganisationModel(
                uuid: UUID().uuidString,
                name: name,
                description: description,
                subscriptions: [],
                tenantUID: tenant.model.uuid,
                createdAt: Date(),
                modifiedAt: Date()
            )
            
            let organisation = try await persistenceManager.insert(domain: Organisation(model: organisationModel))
            
            // Sync with backend
            do {
                let remoteOrganisation = try await organisationNetworkService.create(tenantId: tenant.model.uuid, name: name, description: description)
                
                // Update organisation with remote data
                var updatedOrganisation = organisation
                updatedOrganisation.model.uuid = remoteOrganisation.id
                try await persistenceManager.update(domain: updatedOrganisation)
                
                return updatedOrganisation
            } catch {
                // Rollback on network failure
                try await persistenceManager.delete(domain: organisation)
                throw error
            }
        } catch {
            throw error
        }
    }
    
    func getOrganisation(tenantId: String, organisationId: String) async throws -> Organisation {
        try await organisationNetworkService.read(tenantId: tenantId, organisationId: organisationId).toDomain()
    }
    
    func getOrganisations(tenant: Tenant) async throws -> [Organisation] {
        do {
            // Get local organisations first
            let localOrganisations: [Organisation] = try await persistenceManager.query(
                sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            
            // Sync with backend
            do {
                let remoteOrganisations = try await organisationNetworkService.list(tenantId: tenant.model.uuid)
                
                // Update local organisations with remote data
                var updatedOrganisations: [Organisation] = []
                for remoteOrganisation in remoteOrganisations.items {
                    let dateFormatter = ISO8601DateFormatter()
                    let organisationModel = Organisation.OrganisationModel(
                        uuid: remoteOrganisation.id,
                        name: remoteOrganisation.name,
                        description: remoteOrganisation.description,
                        subscriptions: [],
                        tenantUID: tenant.model.uuid,
                        createdAt: dateFormatter.date(from: remoteOrganisation.createdAt) ?? Date(),
                        modifiedAt: dateFormatter.date(from: remoteOrganisation.updatedAt) ?? Date()
                    )
                    
                    let organisation = try await persistenceManager.insert(domain: Organisation(model: organisationModel))
                    updatedOrganisations.append(organisation)
                }
                
                return updatedOrganisations
            } catch {
                if !localOrganisations.isEmpty {
                    return localOrganisations
                } else {
                    throw error
                }
            }
        } catch {
            throw error
        }
    }
    
    func updateOrganisation(organisation: Organisation,
                            tenant: Tenant,
                            name: String,
                            description: String?,
                            localData: @Sendable @escaping (Organisation) -> Void,
                            remoteData: @Sendable @escaping (Result<Organisation, Error>) -> Void) {
        Task {
            do {
                let originalName = organisation.model.name
                let originalDescription = organisation.model.description
                
                // Update locally first
                var updatedOrganisation = organisation
                updatedOrganisation.model.name = name
                updatedOrganisation.model.description = description
                updatedOrganisation.model.modifiedAt = Date()
                try await persistenceManager.update(domain: updatedOrganisation)
                localData(updatedOrganisation)
                
                // Sync with backend
                do {
                    let remoteOrganisation = try await organisationNetworkService.update(tenantId: tenant.model.uuid, organisationId: organisation.model.uuid, name: name, description: description)
                    
                    // Update with remote data
                    updatedOrganisation.model.uuid = remoteOrganisation.id
                    updatedOrganisation.model.name = remoteOrganisation.name
                    try await persistenceManager.update(domain: updatedOrganisation)
                    
                    remoteData(.success(updatedOrganisation))
                } catch {
                    // Rollback on network failure
                    updatedOrganisation.model.name = originalName
                    updatedOrganisation.model.description = originalDescription
                    try await persistenceManager.update(domain: updatedOrganisation)
                    remoteData(.failure(error))
                }
            } catch {
                remoteData(.failure(error))
            }
        }
    }
    
    func deleteOrganisation(organisation: Organisation,
                            tenant: Tenant,
                            localData: @Sendable @escaping () -> Void,
                            remoteData: @Sendable @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                // Delete locally first
                try await persistenceManager.delete(domain: organisation)
                localData()
                
                // Sync with backend
                do {
                    try await organisationNetworkService.delete(tenantId: tenant.model.uuid, organisationId: organisation.model.uuid)
                    remoteData(.success(()))
                } catch {
                    // Rollback on network failure
                    try await persistenceManager.insert(domain: organisation)
                    remoteData(.failure(error))
                }
            } catch {
                remoteData(.failure(error))
            }
        }
    }
} 
