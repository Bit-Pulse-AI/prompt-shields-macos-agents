import SwiftData
import SwiftUI

enum ProfileDomainError: Error {
    case missingUserId
}

extension EnvironmentValues {
    var profileDomainService: ProfileDomainServiceImpl {
        get { self[ProfileDomainServiceKey.self] }
        set { self[ProfileDomainServiceKey.self] = newValue }
    }
}

struct ProfileDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return ProfileDomainServiceImpl()
    }()
}

protocol ProfileDomainService: Sendable {
    var currentProfile: Profile { get async throws }
    func getProfile() async throws -> Profile
    func currentProfile(refresh: Bool) async throws -> Profile
    func acceptTermsAndConditions() async throws -> Profile
}

struct ProfileDomainServiceImpl: ProfileDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var keychainManager: KeychainManager
    @Inject
    private var profileNetworkService: ProfileNetworkService
    @Inject
    private var userDomainService: UserDomainService

    var currentProfile: Profile {
        get async throws {
            try await currentProfile(refresh: false)
        }
    }

    func currentProfile(refresh: Bool) async throws -> Profile {
        if refresh {
            return try await persistenceManager
                .syncLocalWithRemote(
                    domain: try await getProfile()
                )
        } else {
            let profileId = try await userDomainService.currentUser.model.profileId
            do {
                return try await persistenceManager.fetchItem {
                    $0.model.uuid == profileId
                }
            } catch PersistenceManagerError.missingModel {
                return try await persistenceManager
                    .syncLocalWithRemote(
                        domain: try await getProfile()
                    )
            } catch {
                throw error
            }
        }
    }

    func getProfile() async throws -> Profile {
        let result = try await profileNetworkService.getProfile()
        return result.toDomain()
    }

    func acceptTermsAndConditions() async throws -> Profile {
        let result = try await profileNetworkService.acceptTermsAndConditions()
        let profile = result.toDomain()
        var updatedProfile = try await currentProfile(refresh: true)
        updatedProfile.model.acceptedTerms = profile.model.acceptedTerms
        updatedProfile.model.acceptedTermsDate = profile.model.acceptedTermsDate
        try await persistenceManager.update(domain: updatedProfile)
        return updatedProfile
    }
}
