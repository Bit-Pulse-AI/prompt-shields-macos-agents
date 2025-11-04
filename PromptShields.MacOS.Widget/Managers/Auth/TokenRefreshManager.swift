import Foundation
import Auth0
import os

/// Manages token refresh operations independently to avoid circular dependencies
actor TokenRefreshManager {
    static let shared = TokenRefreshManager()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: TokenRefreshManager.self)
    )

    private var isRefreshing = false

    private init() {}

    /// Attempts to refresh the access token using the stored refresh token
    func refreshToken() async throws -> UserAPIResponse {
        // Prevent multiple simultaneous refresh attempts
        guard !isRefreshing else {
            throw AuthError.tokenRefreshFailed
        }

        isRefreshing = true
        defer { isRefreshing = false }

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
                        // Create updated UserAPIResponse with new access token but keeping user info
                        let updatedResponse = UserAPIResponse(
                            id: credentials.id,
                            firstName: credentials.firstName,
                            lastName: credentials.lastName,
                            email: credentials.email,
                            accessToken: newCredentials.accessToken,
                            refreshToken: newCredentials.refreshToken ?? refreshToken, // Keep old refresh token if new one not provided
                            photoURL: credentials.photoURL,
                            createdAt: credentials.createdAt,
                            updatedAt: Date()
                        )
                        continuation.resume(returning: updatedResponse)
                    case .failure(let error):
                        self.logger.error("Token refresh failed: \(error.localizedDescription)")
                        continuation.resume(throwing: AuthError.tokenRefreshFailed)
                    }
                }
        }
    }
}
