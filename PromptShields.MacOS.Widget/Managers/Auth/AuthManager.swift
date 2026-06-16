import Foundation
import os

extension Notification.Name {
    static let tokenRefreshFailed = Notification.Name("tokenRefreshFailed")
}

enum AuthError: Error, LocalizedError {
    case missingLocalId
    case currentUserNotFound
    case missingTokenEmail
    case tokenRefreshFailed
    case noRefreshTokenAvailable
    case tokenExpired
    case unauthorizedAccess
    case loginFailed

    var errorDescription: String? {
        switch self {
        case .missingLocalId:
            return "Local user ID is missing"
        case .currentUserNotFound:
            return "Current user not found in database"
        case .missingTokenEmail:
            return "Email not found in authentication token"
        case .tokenRefreshFailed:
            return "Failed to refresh authentication token"
        case .noRefreshTokenAvailable:
            return "No refresh token available for authentication renewal"
        case .tokenExpired:
            return "Authentication token has expired"
        case .unauthorizedAccess:
            return "Unauthorized access - authentication required"
        case .loginFailed:
            return "Login failed"
        }
    }
}

// MARK: - Authentication Manager Protocol

protocol AuthenticationManager: Sendable {
    func validateSession() async -> AuthState
    @MainActor func login() async throws -> AuthState
    func logout() async throws
}

// MARK: - Authentication Manager Implementation

actor AuthenticationManagerImpl: AuthenticationManager {
    static let shared = AuthenticationManagerImpl()

    @Inject private var keychainManager: KeychainManager
    @Inject private var persistenceManager: PersistenceManager
    @Inject private var userNetworkService: UserNetworkService
    @Inject private var profileNetworkService: ProfileNetworkService

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "AuthenticationManager"
    )

    private init() {}

    // MARK: - Session Validation (App Reopen)
    func validateSession() async -> AuthState {
        guard let credentials = try? keychainManager.loadUserCredentials(),
              credentials.refreshToken != nil else {
            logger.debug("No stored credentials — session invalid")
            return .loggedOut(nil)
        }

        do {
            let refreshed = try await TokenRefreshManager.shared.refreshToken()
            try keychainManager.saveUserCredentials(userCredentials: refreshed)
            logger.debug("Token refreshed successfully during session validation")
        } catch {
            logger.debug("Token refresh failed: \(error.localizedDescription)")
            await cleanUp()
            return .loggedOut(nil)
        }

        do {
            try await ensureLocalDataExists()
            return try await resolveTermsState()
        } catch {
            logger.debug("Local data verification failed: \(error.localizedDescription)")
            await cleanUp()
            return .loggedOut(nil)
        }
    }

    // MARK: - Login

    /// Performs a full Auth0 login flow:
    /// 1. Clears stale data
    /// 2. Opens Auth0 web login
    /// 3. Persists credentials & encryption key
    /// 4. Creates local user + profile in SwiftData
    /// 5. Checks terms acceptance
    func login() async throws -> AuthState {
        await cleanUp()

        let credentials: UserAPIResponse
        do {
            credentials = try await userNetworkService.login()
        } catch {
            logger.debug("Auth0 login failed: \(error.localizedDescription)")
            throw AuthError.loginFailed
        }

        try keychainManager.saveUserCredentials(userCredentials: credentials)
        try keychainManager.saveEncryptionKey()
        logger.debug("Credentials and encryption key saved")

        try await setupLocalUser(from: credentials)

        return try await resolveTermsState()
    }

    // MARK: - Logout

    /// Clears Auth0 session and all local data.
    nonisolated func logout() async throws {
        try? await userNetworkService.logout()
        await cleanUp()
    }

    // MARK: - Private Helpers

    /// Fetches the profile from the backend and checks whether the user
    /// has accepted the current terms and conditions.
    private func resolveTermsState() async throws -> AuthState {
        let credentials = try keychainManager.loadUserCredentials()
        let profileResponse = try await profileNetworkService.getProfile()
        let profile = profileResponse.toDomain()

        try await persistenceManager.syncLocalWithRemote(domain: profile)

        let shaId = try credentials.id.sha512
        if profile.model.acceptedTerms == shaId {
            return .loggedIn
        } else {
            return .acceptTerms
        }
    }

    /// Checks whether a local user exists in SwiftData; creates one if missing.
    private func ensureLocalDataExists() async throws {
        let credentials = try keychainManager.loadUserCredentials()
        do {
            let _: User = try await persistenceManager.fetchItem(uid: credentials.id)
        } catch PersistenceManagerError.missingModel {
            try await setupLocalUser(from: credentials)
        }
    }

    /// Creates the local user, profile, and preferences in SwiftData.
    /// Network calls (profile fetch) use the freshly-stored access token.
    private func setupLocalUser(from credentials: UserAPIResponse) async throws {
        let profileResponse = try await profileNetworkService.getProfile()
        let profile = profileResponse.toDomain()
        try await persistenceManager.syncLocalWithRemote(domain: profile)

        let preferences = UserPreferences(
            model: .init(uuid: UUID().uuidString, enabledSuggestionTypes: nil)
        )
        let savedPreferences = try await persistenceManager.insert(domain: preferences)

        let user = credentials.toDomain(
            profileId: profile.model.uuid,
            preferenceId: savedPreferences.model.uuid
        )
        try await persistenceManager.insert(domain: user)
        logger.debug("Local user created for \(credentials.email ?? "unknown")")

        // Push the new Person into AI-SPM so the dashboard can hang
        // organisational metadata off it (Department, Owner, etc.). Auth0
        // `id` is the `sub` claim — the same key the dashboard uses for
        // dedupe. Best-effort: failure logs and drops, no UX impact.
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let displayName = "\(credentials.firstName) \(credentials.lastName)"
            .trimmingCharacters(in: .whitespaces)
        let request = PersonSyncRequest(
            auth0Sub: credentials.id,
            email: credentials.email ?? "",
            componentName: displayName.isEmpty ? (credentials.email ?? "Unknown") : displayName,
            role: nil,
            organizationalUnitId: nil,
            appVersion: appVersion
        )
        Task { @MainActor in
            await TelemetryClient.shared.syncPerson(request)
        }
    }

    /// Removes all local auth artifacts: keychain credentials,
    /// encryption key, and SwiftData entries.
    private func cleanUp() async {
        try? keychainManager.deleteUserCredentials()
        try? keychainManager.deleteEncryptionKey()
        try? await persistenceManager.logout()
    }
}
