import SwiftData
import SwiftUI
import Foundation
import os

enum SubscriptionServiceError: Error {
    case missingSubscription
    case missingOrganisation
    case missingCurrentUserId
    case invalidSubscriptionFormat
    case networkError(Error)
}

extension EnvironmentValues {
    var subscriptionDomainService: SubscriptionDomainServiceImpl {
        get { self[SubscriptionDomainServiceKey.self] }
        set { self[SubscriptionDomainServiceKey.self] = newValue }
    }
}

struct SubscriptionDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return SubscriptionDomainServiceImpl()
    }()
}

protocol SubscriptionDomainService: Sendable {
    var currentSubscription: Subscription { get async throws }
    func currentSubscription(refresh: Bool) async throws -> Subscription
}

struct SubscriptionDomainServiceImpl: SubscriptionDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var subscriptionNetworkService: SubscriptionNetworkService
    @Inject
    private var organisationDomainService: OrganisationDomainService
    @Inject
    private var profileDomainService: ProfileDomainService

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SubscriptionDomainService.self)
    )

    var currentSubscription: Subscription {
        get async throws {
            try await currentSubscription(refresh: false)
        }
    }

    func currentSubscription(refresh: Bool) async throws -> Subscription {
        let fetchRemote: () async throws -> Subscription = {
            let currentProfile = try await profileDomainService.currentProfile
            return try await getSubscription(
                organisationId: currentProfile.model.defaultOrganisationId,
                subscriptionId: currentProfile.model.defaultSubscriptionId)
        }
        if refresh {
            return try await persistenceManager.syncLocalWithRemote(domain: fetchRemote())
        } else {
            let currentProfile = try await profileDomainService.currentProfile
            do {
                return try await persistenceManager.fetchItem(filter: { $0.model.uuid == currentProfile.model.defaultSubscriptionId })
            } catch PersistenceManagerError.missingModel {
                return try await persistenceManager.syncLocalWithRemote(domain: fetchRemote())
            } catch {
                throw error
            }
        }
    }

    func getSubscription(organisationId: String, subscriptionId: String) async throws -> Subscription {
        try await subscriptionNetworkService.read(organisationId: organisationId, subscriptionId: subscriptionId).toDomain()
    }
}
