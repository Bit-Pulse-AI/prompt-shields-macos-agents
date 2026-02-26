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
}

struct OrganisationDomainServiceImpl: OrganisationDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var organisationDomainService: OrganisationDomainService
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

    func getOrganisation(tenantId: String, organisationId: String) async throws -> Organisation {
        try await organisationDomainService.currentOrganisation
    }
}
