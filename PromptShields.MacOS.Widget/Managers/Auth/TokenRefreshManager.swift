import Foundation
import os
import Auth0

/// Manages token refresh operations with proper request coalescing.
/// When multiple callers request a refresh concurrently, only one
/// Auth0 call is made and all callers receive the same result.
actor TokenRefreshManager {
    static let shared = TokenRefreshManager()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: TokenRefreshManager.self)
    )

    private var pendingContinuations: [CheckedContinuation<UserAPIResponse, Error>] = []
    private var isRefreshing = false

    private init() {}

    /// Refreshes the access token using the stored refresh token.
    /// Concurrent calls are coalesced into a single Auth0 request.
    func refreshToken() async throws -> UserAPIResponse {
        if isRefreshing {
            return try await withCheckedThrowingContinuation { continuation in
                pendingContinuations.append(continuation)
            }
        }

        isRefreshing = true

        do {
            let result = try await performRefresh()
            resumeAll(with: .success(result))
            return result
        } catch {
            resumeAll(with: .failure(error))
            throw error
        }
    }

    // MARK: - Private

    private func resumeAll(with result: Result<UserAPIResponse, Error>) {
        let waiting = pendingContinuations
        pendingContinuations.removeAll()
        isRefreshing = false

        for continuation in waiting {
            continuation.resume(with: result)
        }
    }

    private nonisolated func performRefresh() async throws -> UserAPIResponse {
        let keychainManager = KeychainManagerImpl.shared
        let credentials = try keychainManager.loadUserCredentials()

        guard let refreshToken = credentials.refreshToken else {
            throw AuthError.noRefreshTokenAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            Auth0
                .authentication()
                .renew(withRefreshToken: refreshToken)
                .start { result in
                    switch result {
                    case .success(let newCredentials):
                        let updated = UserAPIResponse(
                            id: credentials.id,
                            firstName: credentials.firstName,
                            lastName: credentials.lastName,
                            email: credentials.email,
                            accessToken: newCredentials.accessToken,
                            refreshToken: newCredentials.refreshToken ?? refreshToken,
                            photoURL: credentials.photoURL,
                            createdAt: credentials.createdAt,
                            updatedAt: Date()
                        )
                        continuation.resume(returning: updated)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
        }
    }
}
