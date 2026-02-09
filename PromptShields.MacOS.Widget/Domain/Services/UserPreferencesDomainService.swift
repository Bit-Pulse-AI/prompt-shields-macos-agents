import SwiftData
import SwiftUI
import os

extension EnvironmentValues {
    var userPreferencesDomainService: UserPreferencesDomainServiceImpl {
        get { self[UserPreferencesDomainServiceKey.self] }
        set { self[UserPreferencesDomainServiceKey.self] = newValue }
    }
}

struct UserPreferencesDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return UserPreferencesDomainServiceImpl()
    }()
}

protocol UserPreferencesDomainService: Sendable {
    func newPreferences() async throws -> UserPreferences
    func currentUserPreferences() async throws -> UserPreferences
}

struct UserPreferencesDomainServiceImpl: UserPreferencesDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var keychainManager: KeychainManager
    @Inject
    private var userDomainService: UserDomainService

    private let logger: os.Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: UserDomainServiceImpl.self)
    )

    func currentUserPreferences() async throws -> UserPreferences {
        let currentUser = try await userDomainService.currentUser
        let preferenceId = currentUser.model.preferenceId
        do {
            return try await persistenceManager.fetchItem {
                $0.model.uuid == preferenceId
            }
        } catch PersistenceManagerError.missingModel {
            return try await persistenceManager
                .syncLocalWithRemote(
                    domain: try await newPreferences()
                )
        } catch {
            throw error
        }
    }

    func savePreferences(preferences: UserPreferences) async throws {
        try await persistenceManager.update(domain: preferences)
    }

    func newPreferences() async throws -> UserPreferences {
        // Initialize with nil to indicate "all types enabled" (not yet configured)
        // When user explicitly toggles off a type, it will be removed from the list
        let preference = UserPreferences(model: .init(uuid: UUID().uuidString,
                                                      enabledSuggestionTypes: nil,
                                                      useLocalProcessing: false))
        return try await persistenceManager.insert(domain: preference)
    }
}
