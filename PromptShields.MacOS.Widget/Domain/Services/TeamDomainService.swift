import SwiftData
import SwiftUI
import Foundation
import os

enum TeamServiceError: Error {
    case missingTeam
    case missingSubscription
    case missingOrganisation
    case missingCurrentUserId
    case invalidTeamFormat
    case networkError(Error)
}

extension EnvironmentValues {
    var teamDomainService: TeamDomainServiceImpl {
        get { self[TeamDomainServiceKey.self] }
        set { self[TeamDomainServiceKey.self] = newValue }
    }
}

struct TeamDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return TeamDomainServiceImpl()
    }()
}

protocol TeamDomainService: Sendable {
    var currentTeam: Team { get async throws }
    func currentTeam(refresh: Bool) async throws -> Team
}

struct TeamDomainServiceImpl: TeamDomainService {
    @Inject
    private var teamNetworkService: TeamNetworkService
    @Inject
    private var subscriptionDomainService: SubscriptionDomainService
    @Inject
    private var profileDomainService: ProfileDomainService
    @Inject
    private var persistenceManager: PersistenceManager

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: TeamDomainService.self)
    )

    var currentTeam: Team {
        get async throws {
            try await currentTeam(refresh: false)
        }
    }

    func currentTeam(refresh: Bool) async throws -> Team {
        let fetchRemote: () async throws -> Team = {
            let currentProfile = try await profileDomainService.currentProfile
            return try await getTeam(subscriptionId: currentProfile.model.defaultSubscriptionId, teamId: currentProfile.model.defaultTeamId)
        }
        if refresh {
            return try await persistenceManager.syncLocalWithRemote(domain: fetchRemote())
        } else {
            let currentProfile = try await profileDomainService.currentProfile
            do {
                return try await persistenceManager.fetchItem(filter: { $0.model.uuid == currentProfile.model.defaultTeamId })
            } catch PersistenceManagerError.missingModel {
                return try await persistenceManager.syncLocalWithRemote(domain: fetchRemote())
            } catch {
                throw error
            }
        }
    }

    func getTeam(subscriptionId: String, teamId: String) async throws -> Team {
        try await teamNetworkService.read(subscriptionId: subscriptionId, teamId: teamId).toDomain()
    }
}
