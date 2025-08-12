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
    var currentUserPreferences: UserPreferences { get async throws }
    
    func getPreferences() async throws -> UserPreferences
    func currentUserPreferences(refresh: Bool) async throws -> UserPreferences
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
    
    var currentUserPreferences: UserPreferences {
        get async throws {
            try await currentUserPreferences(refresh: false)
        }
    }
    
    func currentUserPreferences(refresh: Bool) async throws -> UserPreferences {
        if refresh {
            return try await persistenceManager
                .syncLocalWithRemote(
                    domain: try await getPreferences()
                )
        } else {
            let currentUser = try await userDomainService.currentUser
            let preferenceId = currentUser.model.preferenceId
            do {
                return try await persistenceManager.fetchItem {
                    $0.model.uuid == preferenceId
                }
            } catch PersistenceManagerError.missingModel {
                return try await persistenceManager
                    .syncLocalWithRemote(
                        domain: try await getPreferences()
                    )
            } catch {
                throw error
            }
        }
    }
    
    func savePreferences(preferences: UserPreferences) async throws {
        try await persistenceManager.update(domain: preferences)
    }
    
    func getPreferences() async throws -> UserPreferences {
        let preference = UserPreferences(model: .init(uuid: UUID().uuidString,
                                                      isEnabled: true,
                                                      enabledSuggestionTypes: [],
                                                      blockedApplications: [],
                                                      language: "en",
                                                      autoApplySuggestions: false,
                                                      showFloatingPanel: true,
                                                      panelPosition: .right,
                                                      lastUpdated: Date()))
        return try await persistenceManager.insert(domain: preference)
    }
}
