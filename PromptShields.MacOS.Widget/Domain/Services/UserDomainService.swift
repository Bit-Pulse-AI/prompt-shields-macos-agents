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
    func deleteAll() async throws
}

struct UserDomainServiceImpl: UserDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var keychainManager: KeychainManager
    @Inject
    private var userNetworkService: UserNetworkService
    @Inject
    private var profileNetworkService: ProfileNetworkService

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
                    domain: try await fetchRemoteUser()
                )
        } else {
            let credentials = try keychainManager.loadUserCredentials()
            return try await persistenceManager.fetchItem(uid: credentials.id)
        }
    }

    func deleteAll() async throws {
        try await persistenceManager.logout()
        try? keychainManager.deleteUserCredentials()
        try? keychainManager.deleteEncryptionKey()
    }

    // MARK: - Private

    private func fetchRemoteUser() async throws -> User {
        let result = try await userNetworkService.getUser()
        let profile = try await profileNetworkService.getProfile()
        return result.toDomain(profileId: profile.id, preferenceId: nil)
    }
}
