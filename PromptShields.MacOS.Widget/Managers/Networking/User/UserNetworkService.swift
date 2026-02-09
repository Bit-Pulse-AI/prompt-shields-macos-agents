import Foundation
import Auth0
import JWTDecode
import os

enum UserNetworkServiceError: Error {
    case missingUserInfo
    case missingSub
    case tokenRefreshFailed
    case noRefreshTokenAvailable
}

protocol UserNetworkService: NetworkService {
    @MainActor func login() async throws -> UserAPIResponse
    @MainActor func logout() async throws
    @MainActor func getUser() async throws -> UserAPIResponse
    func refreshToken() async throws -> UserAPIResponse
}

struct UserNetworkServiceImpl: UserNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager

    private let logger: os.Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: UserNetworkServiceImpl.self)
    )

    nonisolated func getUser() async throws -> UserAPIResponse {
        let credentials = try keychainManager.loadUserCredentials()
        let accessToken = credentials.accessToken
        let existingRefreshToken = credentials.refreshToken

        return try await withCheckedThrowingContinuation { continuation in
            Auth0
                .authentication()
                .userInfo(withAccessToken: accessToken)
                .start { result in
                    switch result {
                    case .success(let userInfo):
                        let userAPIResponse = Self.convertAuth0UserToAPIResponse(userInfo, accessToken: accessToken, existingRefreshToken: existingRefreshToken)
                        Task {
                            await MainActor.run {
                                continuation.resume(returning: userAPIResponse)
                            }
                        }
                    case .failure(let error):
                        Task {
                            await MainActor.run {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
        }
    }

    nonisolated func logout() async throws {
        let logger = self.logger
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                Auth0
                    .webAuth()
                    .clearSessionIsolated { result in
                        switch result {
                        case .success:
                            logger.debug("Session cleared successfully")

                            Task {
                                await MainActor.run {
                                    continuation.resume(returning: ())
                                }
                            }
                        case .failure(let error):
                            logger.debug("Session error while clearing: \(error.localizedDescription)")

                            Task {
                                await MainActor.run {
                                    continuation.resume(throwing: UserNetworkServiceError.missingUserInfo)
                                }
                            }
                        }
                    }
            }
        }
    }

    @MainActor
    func login() async throws -> UserAPIResponse {
        return try await withCheckedThrowingContinuation { continuation in
            Auth0
                .webAuth(session: .shared, bundle: .main)
                .audience(auth0audience)
                .scope("openid profile email offline_access").start { result in
                    do {
                        let credentials = try result.get()
                        Task {
                            try await MainActor.run {
                                continuation.resume(with: .success(try credentials.decode()))
                            }
                        }
                    } catch {
                        Task {
                            await MainActor.run {
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
        }
    }

    func refreshToken() async throws -> UserAPIResponse {
        return try await TokenRefreshManager.shared.refreshToken()
    }

    private static func convertAuth0UserToAPIResponse(
        _ userInfo: UserInfo,
        accessToken: String,
        existingRefreshToken: String?
    ) -> UserAPIResponse {
        let userId = userInfo.sub
        let email = userInfo.email
        let firstName = userInfo.givenName ?? "n/a"
        let lastName = userInfo.familyName ?? "n/a"
        let photoURL = userInfo.picture?.absoluteString

        return UserAPIResponse(id: userId,
                               firstName: firstName,
                               lastName: lastName,
                               email: email,
                               accessToken: accessToken,
                               refreshToken: existingRefreshToken,
                               photoURL: photoURL,
                               createdAt: Date(),
                               updatedAt: Date())
    }
}

private extension Credentials {
    func decode() throws -> UserAPIResponse {
        let decodedToken = try JWTDecode.decode(jwt: idToken)
        let email = decodedToken["email"].string
        guard let sub = decodedToken["sub"].string else {
            throw UserNetworkServiceError.missingSub
        }
        let firstName = decodedToken["given_name"].string ?? "n/a"
        let lastName = decodedToken["family_name"].string ?? "n/a"
        let photoURL = decodedToken["picture"].string

        return UserAPIResponse(id: sub,
                               firstName: firstName,
                               lastName: lastName,
                               email: email,
                               accessToken: accessToken,
                               refreshToken: refreshToken,
                               photoURL: photoURL,
                               createdAt: Date(),
                               updatedAt: Date())
    }
}

extension WebAuth {
    @MainActor
    func clearSessionIsolated(callback: @escaping (WebAuthResult<Void>) -> Void) {
        clearSession(federated: false, callback: callback)
    }
}
