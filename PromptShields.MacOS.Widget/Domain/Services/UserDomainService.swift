import SwiftData
import SwiftUI
import os

extension EnvironmentValues {
    var userDomainService: UserDomainServiceImpl {
        get { self[UserDomainServiceKey.self] }
        set { self[UserDomainServiceKey.self] = newValue }
    }
}

struct UserDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return UserDomainServiceImpl()
    }()
}

protocol UserDomainService: Sendable {
    var currentUser: User { get async throws }

    func currentUser(refresh: Bool) async throws -> User
    func login() async throws -> User
    func logout() async throws
}

struct UserDomainServiceImpl: UserDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var keychainManager: KeychainManager
    @Inject
    private var userNetworkService: UserNetworkService
    @Inject
    private var profileDomainService: ProfileDomainService
    @Inject
    private var preferenceDomainService: UserPreferencesDomainService

    private let logger: os.Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: UserDomainServiceImpl.self)
    )

    var currentUser: User {
        get async throws {
            try await currentUser(refresh: false)
        }
    }

    func currentUser(refresh: Bool) async throws -> User {
        if refresh {
            return try await persistenceManager
                .syncLocalWithRemote(
                    domain: try await getUser()
                )
        } else {
            let credentials = try keychainManager.loadUserCredentials()
            let userId = credentials.id

            do {
                return try await persistenceManager.fetchItem(uid: userId)
            } catch PersistenceManagerError.missingModel {
                return try await persistenceManager
                    .syncLocalWithRemote(
                        domain: try await getUser()
                    )
            } catch {
                throw error
            }
        }
    }

    @MainActor
    func login() async throws -> User {
        do {
            let existingUser = try await currentUser
            logger.log("Existing user: user with email '\(existingUser.model.email)' present")
            return existingUser
        } catch {
            do {
                logger.log("Existing user or user credentials missing ...")
                logger.log("Cleaning auth up ...")
                try? await deleteAll()
                logger.log("Executing authentication ...")
                let credentials = try await userNetworkService.login()
                logger.log("Saving credentials")
                try keychainManager.saveUserCredentials(userCredentials: credentials)
                logger.log("Create new encryption key")
                try createNewEncryptionKey()
                logger.log("Create new local user")
                let user = try await createNewLocalUser()
                logger.log("Created local user ✅")
                return user
            } catch {
                logger.error("Sequence failed \(error)")
                throw UserNetworkServiceError.missingUserInfo
            }
        }
    }

    func logout() async throws {
        try await userNetworkService.logout()
        try await deleteAll()
    }

    private func getUser() async throws -> User {
        let result = try await userNetworkService.getUser()
        let profile = try await profileDomainService.getProfile()
        let preferences = try await preferenceDomainService.getPreferences()
        return result.toDomain(profileId: profile.model.uuid, preferenceId: preferences.model.uuid)
    }

    func deleteAll() async throws {
        try await deleteLocalData()
        try deleteCredentials()
        try await deleteEncryptionKey()
    }

    private func deleteCredentials() throws {
        try keychainManager.deleteUserCredentials()
    }

    private func deleteLocalData() async throws {
        try await persistenceManager.logout()
    }

    private func deleteEncryptionKey() async throws {
        try keychainManager.deleteEncryptionKey()
    }

    private func createNewLocalUser() async throws -> User {
        let credentials = try keychainManager.loadUserCredentials()
        let currentProfile = try await profileDomainService.getProfile()
        let currentPreferences = try await preferenceDomainService.getPreferences()
        let currentUser: User = credentials.toDomain(profileId: currentProfile.model.uuid, preferenceId: currentPreferences.model.uuid)
        let persistenceManager = PersistenceManagerImpl.shared
        try await persistenceManager.insert(domain: currentUser)
        return currentUser
    }

    private func createNewEncryptionKey() throws {
        try keychainManager.saveEncryptionKey()
    }
}
