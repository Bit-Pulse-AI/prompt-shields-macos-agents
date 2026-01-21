import SwiftData
import SwiftUI
import Foundation
import os

extension EnvironmentValues {
    var suggestionDomainService: SuggestionDomainServiceImpl {
        get { self[SuggestionDomainServiceKey.self] }
        set { self[SuggestionDomainServiceKey.self] = newValue }
    }
}

struct SuggestionDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return SuggestionDomainServiceImpl()
    }()
}

// MARK: - Protocol

protocol SuggestionDomainService: Sendable {
    // Suggestion processing
    @discardableResult
    func process(text: String,
                 suggestionGroupId: String,
                 teamId: String,
                 suggestionType: String,
                 application: String) async throws -> Suggestion
    func fetchCurrentSuggestionGroup() async throws -> SuggestionGroup
    func list(offset: Int, limit: Int) async throws

    // Suggestion Type operations
    func fetchSuggestionTypes() async throws
    func listSuggestionTypes(enabledOnly: Bool) async throws -> [SuggestionType]
    func createSuggestionType(_ suggestionType: SuggestionType) async throws -> SuggestionType
    func updateSuggestionType(_ suggestionType: SuggestionType) async throws -> SuggestionType
    func deleteSuggestionType(_ suggestionType: SuggestionType) async throws
    func toggleSuggestionType(_ suggestionType: SuggestionType, isEnabled: Bool) async throws -> SuggestionType
    func resetSuggestionTypes() async throws -> Int
}

// MARK: - Implementation

struct SuggestionDomainServiceImpl: SuggestionDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var suggestionNetworkService: SuggestionNetworkService
    @Inject
    private var userDomainService: UserDomainService
    @Inject
    private var profileDomainService: ProfileDomainService
    @Inject
    private var userPreferenceDomainService: UserPreferencesDomainService

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "SuggestionDomainService"
    )

    private let path = "suggestion"

    // MARK: - Suggestion Processing

    @discardableResult
    func process(text: String,
                 suggestionGroupId: String,
                 teamId: String,
                 suggestionType: String,
                 application: String) async throws -> Suggestion {
        let suggestionResult = try await suggestionNetworkService.analyze(text: text,
                                                                          suggestionGroupId: suggestionGroupId,
                                                                          teamId: teamId,
                                                                          suggestionType: suggestionType,
                                                                          application: application)
        return suggestionResult.toDomain()
    }

    func list(offset: Int, limit: Int) async throws {
        if offset == 0 {
            let existingSuggestions: [Suggestion] = try await persistenceManager.query()
            try await persistenceManager.delete(domains: existingSuggestions)
        }
        let currentProfile = try await profileDomainService.currentProfile.model
        let suggestionGroupId = currentProfile.defaultSuggestionGroupId
        let teamId = currentProfile.defaultTeamId
        let suggestionsResult = try await suggestionNetworkService
            .listSuggestions(
                suggestionGroupId: suggestionGroupId,
                teamId: teamId,
                offset: offset,
                limit: limit)
        let suggestions = suggestionsResult.toDomain()
        try await persistenceManager.syncLocalWithRemote(domains: suggestions)
    }

    func fetchSuggestionGroup(suggestionGroupId: String, teamId: String) async throws -> SuggestionGroup {
        let suggestionGroup = try await suggestionNetworkService.fetchSuggestionGroup(suggestionGroupId: suggestionGroupId, teamId: teamId)
        return try await persistenceManager.syncLocalWithRemote(domain: suggestionGroup.toDomain())
    }

    func fetchSuggestionTypeGroup(suggestionTypeGroupId: String, teamId: String) async throws -> SuggestionTypeGroup {
        let suggestionTypeGroup = try await suggestionNetworkService.fetchSuggestionTypeGroup(suggestionTypeGroupId: suggestionTypeGroupId, teamId: teamId)
        return try await persistenceManager.syncLocalWithRemote(domain: suggestionTypeGroup.toDomain())
    }

    func fetchCurrentSuggestionGroup() async throws -> SuggestionGroup {
        let currentProfile = try await profileDomainService.currentProfile.model
        let suggestionGroupId = currentProfile.defaultSuggestionGroupId
        let teamId = currentProfile.defaultTeamId
        let currentSuggestionGroup = try await fetchSuggestionGroup(suggestionGroupId: suggestionGroupId, teamId: teamId)
        return currentSuggestionGroup
    }

    func fetchCurrentSuggestionTypeGroup() async throws -> SuggestionTypeGroup {
        let currentProfile = try await profileDomainService.currentProfile.model
        let suggestionTypeGroupId = currentProfile.defaultSuggestionTypeGroupId
        let teamId = currentProfile.defaultTeamId
        let currentSuggestionTypeGroup = try await fetchSuggestionTypeGroup(suggestionTypeGroupId: suggestionTypeGroupId, teamId: teamId)
        return currentSuggestionTypeGroup
    }

    // MARK: - Suggestion Type CRUD Operations

    func fetchSuggestionTypes() async throws {
        logger.debug("Fetching suggestion types from server")

        do {
            // Try the new endpoint first
            let currentProfile = try await profileDomainService.currentProfile.model
            let suggestionTypeGroupId = currentProfile.defaultSuggestionTypeGroupId
            let suggestionResult = try await suggestionNetworkService.listSuggestionTypes(suggestionTypeGroupId: suggestionTypeGroupId, offset: 0, limit: 100, enabledOnly: false)
            let suggestionTypes = suggestionResult.toDomain()

            // Atomic delete and insert - prevents duplicates from race conditions
            try await persistenceManager.deleteAllAndInsert(domains: suggestionTypes)

            logger.debug("Fetched \(suggestionTypes.count) suggestion types from new endpoint")
        } catch {
            logger.debug("Endpoint failed: \(error)")
        }

        // Update user preferences to populate all types as enabled if nil
        await updateUserPreferencesWithEnabledTypes()
    }

    func listSuggestionTypes(enabledOnly: Bool) async throws -> [SuggestionType] {
        // First try to get from local cache
        let localTypes: [SuggestionType] = try await persistenceManager.query(
            sortDescriptors: [SortDescriptor(\.sortOrder, order: .forward)]
        )

        if !localTypes.isEmpty {
            if enabledOnly {
                return localTypes.filter { $0.model.isEnabled }
            }
            return localTypes
        }

        // If no local types, fetch from server
        try await fetchSuggestionTypes()

        let updatedTypes: [SuggestionType] = try await persistenceManager.query(
            sortDescriptors: [SortDescriptor(\.sortOrder, order: .forward)]
        )

        if enabledOnly {
            return updatedTypes.filter { $0.model.isEnabled }
        }
        return updatedTypes
    }

    func createSuggestionType(_ suggestionType: SuggestionType) async throws -> SuggestionType {
        logger.debug("Creating suggestion type: \(suggestionType.model.name)")

        let request = CreateSuggestionTypeRequest(
            typeKey: suggestionType.model.typeKey.uppercased().replacingOccurrences(of: " ", with: "_"),
            name: suggestionType.model.name,
            description: suggestionType.model.description,
            category: suggestionType.model.category,
            promptTemplate: suggestionType.model.promptTemplate,
            suggestionTypeGroupId: suggestionType.model.suggestionTypeGroupId,
            icon: suggestionType.model.icon,
            isEnabled: suggestionType.model.isEnabled,
            sortOrder: suggestionType.model.sortOrder
        )

        let response = try await suggestionNetworkService.createSuggestionType(request: request)
        let createdType = response.toDomain()

        // Sync with local storage
        let syncedType = try await persistenceManager.syncLocalWithRemote(domain: createdType)

        logger.debug("Created suggestion type: \(syncedType.model.uuid)")
        return syncedType
    }

    func updateSuggestionType(_ suggestionType: SuggestionType) async throws -> SuggestionType {
        logger.debug("Updating suggestion type: \(suggestionType.model.uuid)")

        let currentProfile = try await profileDomainService.currentProfile.model
        let suggestionTypeGroupId = currentProfile.defaultSuggestionTypeGroupId
        let request = UpdateSuggestionTypeRequest(
            name: suggestionType.model.name,
            description: suggestionType.model.description,
            category: suggestionType.model.category,
            promptTemplate: suggestionType.model.promptTemplate,
            suggestionTypeGroupId: suggestionType.model.suggestionTypeGroupId,
            icon: suggestionType.model.icon,
            isEnabled: suggestionType.model.isEnabled,
            sortOrder: suggestionType.model.sortOrder
        )

        let response = try await suggestionNetworkService.updateSuggestionType(suggestionTypeGroupId, suggestionTypeId: suggestionType.model.uuid, request: request)
        let updatedType = response.toDomain()

        // Sync with local storage
        let syncedType = try await persistenceManager.syncLocalWithRemote(domain: updatedType)

        logger.debug("Updated suggestion type: \(syncedType.model.uuid)")
        return syncedType
    }

    func deleteSuggestionType(_ suggestionType: SuggestionType) async throws {
        let currentProfile = try await profileDomainService.currentProfile.model
        let suggestionTypeGroupId = currentProfile.defaultSuggestionTypeGroupId
        // Delete from server
        try await suggestionNetworkService.deleteSuggestionType(suggestionTypeGroupId, suggestionTypeId: suggestionType.model.uuid)

        // Delete from local storage
        try await persistenceManager.delete(domain: suggestionType)

        logger.debug("Deleted suggestion type: \(suggestionType.model.uuid)")
    }

    func toggleSuggestionType(_ suggestionType: SuggestionType, isEnabled: Bool) async throws -> SuggestionType {
        logger.debug("Toggling suggestion type \(suggestionType.model.uuid) to enabled: \(isEnabled)")

        let currentProfile = try await profileDomainService.currentProfile.model
        let suggestionTypeGroupId = currentProfile.defaultSuggestionTypeGroupId
        let response = try await suggestionNetworkService.toggleSuggestionType(suggestionTypeGroupId: suggestionTypeGroupId, suggestionTypeId: suggestionType.model.uuid, isEnabled: isEnabled)
        let updatedType = response.toDomain()

        // Sync with local storage
        let syncedType = try await persistenceManager.syncLocalWithRemote(domain: updatedType)

        logger.debug("Toggled suggestion type: \(syncedType.model.uuid)")
        return syncedType
    }

    func resetSuggestionTypes() async throws -> Int {
        logger.debug("Resetting suggestion types to defaults")
        let currentProfile = try await profileDomainService.currentProfile.model
        let suggestionTypeGroupId = currentProfile.defaultSuggestionTypeGroupId
        let response = try await suggestionNetworkService.resetSuggestionTypes(suggestionTypeGroupId: suggestionTypeGroupId)

        // Refresh local storage
        try await fetchSuggestionTypes()

        logger.debug("Reset suggestion types: \(response.count) defaults created")
        return response.count
    }

    // MARK: - Private Helpers

    private func updateUserPreferencesWithEnabledTypes() async {
        guard let preferenceId = try? await userDomainService.currentUser.model.preferenceId else {
            return
        }

        do {
            var preference: UserPreferences = try await persistenceManager.fetchItem(uid: preferenceId)

            // If enabledSuggestionTypes is nil, populate with all available enabled types
            // This makes all types enabled by default on first load
            if preference.model.enabledSuggestionTypes == nil {
                let allTypes: [SuggestionType] = try await persistenceManager.query()
                let enabledTypeKeys = allTypes
                    .filter { $0.model.isEnabled }
                    .compactMap { $0.model.typeKey }
                preference.model.enabledSuggestionTypes = enabledTypeKeys
                try await persistenceManager.update(domain: preference)
            }
        } catch {
            // Preference not found or update failed - not critical, continue
            logger.debug("Failed to update user preferences with enabled types: \(error)")
        }
    }
}
