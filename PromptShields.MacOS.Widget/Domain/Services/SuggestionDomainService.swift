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

protocol SuggestionDomainService: Sendable {
    @discardableResult
    func process(text: String,
                 llmProvider: String,
                 suggestionGroupId: String,
                 teamId: String,
                 suggestionType: String,
                 application: String) async throws -> Suggestion
    func fetchSuggestionTypes() async throws
    func fetchCurrentSuggestionGroup() async throws -> SuggestionGroup
    func list(offset: Int,
              limit: Int) async throws
}

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

    private let path = "suggestion"

    @discardableResult
    func process(text: String,
                 llmProvider: String,
                 suggestionGroupId: String,
                 teamId: String,
                 suggestionType: String,
                 application: String) async throws -> Suggestion {
        let suggestionResult = try await suggestionNetworkService.analyze(text: text,
                                                                          llmProvider: llmProvider,
                                                                          suggestionGroupId: suggestionGroupId,
                                                                          teamId: teamId,
                                                                          suggestionType: suggestionType,
                                                                          application: application)
        return suggestionResult.toDomain()
    }

    func list(offset: Int,
              limit: Int) async throws {
        if offset == 0 {
            let existingSuggestions: [Suggestion] = try await persistenceManager.query()
            try await persistenceManager.delete(domains: existingSuggestions)
        }
        let currentProfile = try await profileDomainService.currentProfile.model
        let suggestionGroupId = currentProfile.defaultSuggestionGroupId
        let teamId = currentProfile.defaultTeamId
        let suggestionsResult = try await suggestionNetworkService
            .list(
                suggestionGroupId: suggestionGroupId,
                llmProvider: LLMProvider.AZURE_PROMPTSHIELDS.rawValue,
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

    func fetchCurrentSuggestionGroup() async throws -> SuggestionGroup {
        let currentProfile = try await profileDomainService.currentProfile.model
        let suggestionGroupId = currentProfile.defaultSuggestionGroupId
        let teamId = currentProfile.defaultTeamId
        let currentSuggestionGroup = try await fetchSuggestionGroup(suggestionGroupId: suggestionGroupId, teamId: teamId)
        return currentSuggestionGroup
    }

    func fetchSuggestionTypes() async throws {
        let suggestionResult = try await suggestionNetworkService.fetchSuggestionTypes()
        let suggestionTypes = suggestionResult.toDomain()

        // Delete and insert in sequence - actor serializes these operations
        try await persistenceManager.deleteEntity(entity: SuggestionType.self)
        try await persistenceManager.insert(domains: suggestionTypes)

        // Update user preferences to populate all types as enabled if nil
        guard let preferenceId = try? await userDomainService.currentUser.model.preferenceId else {
            return
        }

        do {
            var preference: UserPreferences = try await persistenceManager.fetchItem(uid: preferenceId)

            // If enabledSuggestionTypes is nil, populate with all available types
            // This makes all types enabled by default on first load
            if preference.model.enabledSuggestionTypes == nil {
                let allTypeIds = suggestionTypes.compactMap { $0.model.suggestionType }
                preference.model.enabledSuggestionTypes = allTypeIds
                try await persistenceManager.update(domain: preference)
            }
        } catch {
            // Preference not found or update failed - not critical, continue
        }
    }
}
