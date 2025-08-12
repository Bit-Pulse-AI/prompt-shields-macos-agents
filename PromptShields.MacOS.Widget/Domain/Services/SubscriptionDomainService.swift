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
    
    func getSubscriptions(organisation: Organisation) async throws -> [Subscription]
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
    
    func getSubscriptions(organisation: Organisation) async throws -> [Subscription] {
        do {
            // Get local subscriptions first
            let localSubscriptions: [Subscription] = try await persistenceManager.query(
                sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            
            // Sync with backend
            do {
                let remoteSubscriptions = try await subscriptionNetworkService.list(organisationId: organisation.model.uuid)
                
                // Update local subscriptions with remote data
                var updatedSubscriptions: [Subscription] = []
                for remoteSubscription in remoteSubscriptions.items {
                    let dateFormatter = ISO8601DateFormatter()
                    let subscriptionModel = Subscription.SubscriptionModel(
                        uuid: remoteSubscription.id,
                        name: remoteSubscription.name,
                        tier: remoteSubscription.tier,
                        organisationUID: remoteSubscription.origanisationUID,
                        createdAt: dateFormatter.date(from: remoteSubscription.createdAt) ?? Date(),
                        modifiedAt: dateFormatter.date(from: remoteSubscription.updatedAt) ?? Date()
                    )
                    
                    let subscription = try await persistenceManager.insert(domain: Subscription(model: subscriptionModel))
                    updatedSubscriptions.append(subscription)
                }
                return updatedSubscriptions
            } catch {
                if !localSubscriptions.isEmpty {
                    return localSubscriptions
                } else {
                    throw error
                }
            }
        } catch {
            throw error
        }
    }
} 
