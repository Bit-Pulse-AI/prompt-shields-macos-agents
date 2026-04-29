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
    /// Bypasses the cache TTL — used by Settings' refresh button and after
    /// any mutation that needs the local store immediately resynced.
    func forceRefreshSuggestionTypes() async throws
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

    /// TTL for the suggestion-types cache. Settings + dashboard re-render
    /// fire `fetchSuggestionTypes` on every appear, but server-side types
    /// rarely change. Honour a 5-minute window to avoid hammering the API
    /// every time the user switches tabs. Mutating operations
    /// (create/update/delete/reset) invalidate the cache so the next read
    /// pulls fresh data.
    private static let suggestionTypesCacheTTL: TimeInterval = 300
    private static let suggestionTypesCacheKey = "ai.bit-pulse.promptshields.suggestionTypesFetchedAt"

    func fetchSuggestionTypes() async throws {
        if Self.isSuggestionTypesCacheFresh() {
            logger.debug("Suggestion types cache fresh; skipping server fetch")
            await updateUserPreferencesWithEnabledTypes()
            return
        }
        try await forceRefreshSuggestionTypes()
    }

    /// Always hits the server. Used by reset / create / update / delete to
    /// resync after a write. Settings can also offer a pull-to-refresh that
    /// calls this directly.
    func forceRefreshSuggestionTypes() async throws {
        logger.debug("Force-fetching suggestion types from server")

        do {
            let currentProfile = try await profileDomainService.currentProfile.model
            let suggestionTypeGroupId = currentProfile.defaultSuggestionTypeGroupId
            let suggestionResult = try await suggestionNetworkService.listSuggestionTypes(suggestionTypeGroupId: suggestionTypeGroupId, offset: 0, limit: 100, enabledOnly: false)
            let suggestionTypes = suggestionResult.toDomain()

            // Atomic delete and insert - prevents duplicates from race conditions
            try await persistenceManager.deleteAllAndInsert(domains: suggestionTypes)

            // Cache marker so subsequent fetchSuggestionTypes() calls within
            // TTL skip the server round-trip.
            UserDefaults.standard.set(Date(), forKey: Self.suggestionTypesCacheKey)

            logger.debug("Fetched \(suggestionTypes.count) suggestion types from new endpoint")

            // Seed the catalog-defaults (Redaction today) if the server
            // doesn't already have them. Runs once per suggestion-type-group
            // per user; guarded by UserDefaults so a temporary backend hiccup
            // doesn't spam create-calls on every launch.
            await seedCatalogDefaultsIfNeeded(fetched: suggestionTypes,
                                              suggestionTypeGroupId: suggestionTypeGroupId)
        } catch {
            logger.debug("Endpoint failed: \(error)")
        }

        // Update user preferences to populate all types as enabled if nil
        await updateUserPreferencesWithEnabledTypes()
    }

    /// Auto-creates the catalog's `isDefaultSeeded` types if the server
    /// doesn't already return them. Idempotent: checks by normalised typeKey
    /// and by name, and persists a "seeded" flag per type to avoid duplicate
    /// server-side records.
    private func seedCatalogDefaultsIfNeeded(
        fetched: [SuggestionType],
        suggestionTypeGroupId: String
    ) async {
        let existingKeys = Set(
            fetched.map { normaliseCatalogKey($0.model.typeKey) }
                + fetched.map { normaliseCatalogKey($0.model.name) }
        )

        for entry in SuggestionTypeCatalog.defaultSeededMetadata {
            // Use the displayName to derive the typeKey so Settings and Catalog
            // agree. For Redaction -> typeKey "REDACTION", name "Redaction".
            let candidateTypeKey = SuggestionTypeCatalog.redactionTypeKey
            let normalised = normaliseCatalogKey(candidateTypeKey)

            guard !existingKeys.contains(normalised) else {
                logger.debug("Catalog seed '\(entry.displayName)' already present — skipping")
                continue
            }

            let seededFlagKey = "ai.bit-pulse.promptshields.seeded.\(normalised)"
            guard !UserDefaults.standard.bool(forKey: seededFlagKey) else {
                // Seed was created previously but then deleted by the user.
                // Respect that — don't re-create every launch.
                logger.debug("Catalog seed '\(entry.displayName)' previously seeded and removed — honoring user intent")
                continue
            }

            guard let template = entry.meta.seedPromptTemplate else { continue }

            let seed = SuggestionType(model: .init(
                uuid: UUID().uuidString,
                typeKey: candidateTypeKey,
                name: entry.displayName,
                description: entry.meta.summary,
                category: entry.category,
                promptTemplate: template,
                suggestionTypeGroupId: suggestionTypeGroupId,
                isDefault: true,
                isEnabled: true,
                sortOrder: -100, // float to the top of lists by default
                createdAt: Date(),
                updatedAt: Date()
            ))

            do {
                _ = try await createSuggestionType(seed)
                UserDefaults.standard.set(true, forKey: seededFlagKey)
                logger.debug("Seeded catalog default: \(entry.displayName)")
            } catch {
                logger.error("Failed to seed '\(entry.displayName)': \(error.localizedDescription)")
            }
        }
    }

    private func normaliseCatalogKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
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

    /// True if we last fetched within the TTL window. Pure read against
    /// UserDefaults — safe to call from any actor context.
    static func isSuggestionTypesCacheFresh() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: suggestionTypesCacheKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(last) < suggestionTypesCacheTTL
    }

    /// Drops the cache marker so the next `fetchSuggestionTypes()` hits
    /// the server. Called after every mutating CRUD op.
    private func invalidateSuggestionTypesCache() {
        UserDefaults.standard.removeObject(forKey: Self.suggestionTypesCacheKey)
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
            isEnabled: suggestionType.model.isEnabled,
            sortOrder: suggestionType.model.sortOrder
        )

        let response = try await suggestionNetworkService.createSuggestionType(request: request)
        let createdType = response.toDomain()

        // Sync with local storage
        let syncedType = try await persistenceManager.syncLocalWithRemote(domain: createdType)
        invalidateSuggestionTypesCache()

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
            isEnabled: suggestionType.model.isEnabled,
            sortOrder: suggestionType.model.sortOrder
        )

        let response = try await suggestionNetworkService.updateSuggestionType(suggestionTypeGroupId, suggestionTypeId: suggestionType.model.uuid, request: request)
        let updatedType = response.toDomain()

        // Sync with local storage
        let syncedType = try await persistenceManager.syncLocalWithRemote(domain: updatedType)
        invalidateSuggestionTypesCache()

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
        invalidateSuggestionTypesCache()

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
        invalidateSuggestionTypesCache()

        logger.debug("Toggled suggestion type: \(syncedType.model.uuid)")
        return syncedType
    }

    func resetSuggestionTypes() async throws -> Int {
        logger.debug("Resetting suggestion types to defaults")
        let currentProfile = try await profileDomainService.currentProfile.model
        let suggestionTypeGroupId = currentProfile.defaultSuggestionTypeGroupId
        let response = try await suggestionNetworkService.resetSuggestionTypes(suggestionTypeGroupId: suggestionTypeGroupId)

        // Reset is a server-side mutation; force a fresh fetch so our local
        // store reflects the new defaults immediately rather than waiting
        // for the cache TTL to expire.
        invalidateSuggestionTypesCache()
        try await forceRefreshSuggestionTypes()

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
