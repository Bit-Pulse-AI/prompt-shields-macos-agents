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

    func createTeam(subscription: Subscription,
                    name: String) async throws

    func getTeams(subscription: Subscription) async throws

    func updateTeam(team: Team,
                    subscription: Subscription,
                    name: String?,
                    teamStatus: TeamStatus?) async throws

    func deleteTeam(team: Team,
                    subscription: Subscription) async throws
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

    func createTeam(subscription: Subscription,
                    name: String) async throws {
        do {
            // Create team locally first
            let teamModel = Team.TeamModel(
                uuid: UUID().uuidString,
                name: name,
                description: nil,
                subscription: subscription,
                members: [],
                status: TeamStatus.active.rawValue,
                createdAt: Date(),
                modifiedAt: Date()
            )

            let team = try await persistenceManager.insert(domain: Team(model: teamModel))

            // Sync with backend
            do {
                let remoteTeam = try await teamNetworkService.create(subscriptionId: subscription.model.uuid, name: name)

                // Update team with remote data
                var updatedTeam = team
                updatedTeam.model.uuid = remoteTeam.id
                try await persistenceManager.update(domain: updatedTeam)
            } catch {
                // Rollback on network failure
                try await persistenceManager.delete(domain: team)
                throw error
            }
        } catch {
            throw error
        }
    }

    func getTeam(subscriptionId: String, teamId: String) async throws -> Team {
        try await teamNetworkService.read(subscriptionId: subscriptionId, teamId: teamId).toDomain()
    }

    func getTeams(subscription: Subscription) async throws {
        // Get local teams first
//        let localTeams: [Team] = try await persistenceManager.query(
//            sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)]
//        )
//        do {
//            let remoteTeams = try await teamNetworkService.list(subscriptionId: subscription.model.uuid)
//
//
//            let dateFormatter = ISO8601DateFormatter()
//            for remoteTeam in remoteTeams.items {
//                let teamModel = Team.TeamModel(
//                    uuid: remoteTeam.id,
//                    name: remoteTeam.name,
//                    description: remoteTeam.description,
//                    subscription: subscription,
//                    projects: [],
//                    projectCount: 0,
//                    members: [],
//                    status: remoteTeam.teamStatus,
//                    createdAt: dateFormatter.date(from: remoteTeam.createdAt) ?? Date(),
//                    modifiedAt: dateFormatter.date(from: remoteTeam.updatedAt) ?? Date()
//                )
//            }
//        } catch {
//            if !localTeams.isEmpty {
//            } else {
//                throw error
//            }
//        }
    }

    func updateTeam(team: Team,
                    subscription: Subscription,
                    name: String?,
                    teamStatus: TeamStatus?) async throws {
            do {
                let originalName = team.model.name

                // Update locally first
                var updatedTeam = team
                if let name = name {
                    updatedTeam.model.name = name
                    updatedTeam.model.modifiedAt = Date()
                }
                try await persistenceManager.update(domain: updatedTeam)

                // Sync with backend
                do {
                    let remoteTeam = try await teamNetworkService.update(subscriptionId: subscription.model.uuid, teamId: team.model.uuid, name: name, teamStatus: teamStatus)

                    // Update with remote data
                    updatedTeam.model.uuid = remoteTeam.id
                    updatedTeam.model.name = remoteTeam.name
                    try await persistenceManager.update(domain: updatedTeam)
                } catch {
                    // Rollback on network failure
                    updatedTeam.model.name = originalName
                    try await persistenceManager.update(domain: updatedTeam)
                }
            } catch {
                throw error
            }
    }

    func deleteTeam(team: Team,
                    subscription: Subscription) async throws {
        do {
            // Delete locally first
            try await persistenceManager.delete(domain: team)

            // Sync with backend
            do {
                try await teamNetworkService.delete(subscriptionId: subscription.model.uuid, teamId: team.model.uuid)
            } catch {
                // Rollback on network failure
                try await persistenceManager.insert(domain: team)
            }
        } catch {
            throw error
        }
    }
}
