import Foundation
import Auth0
import os
import JWTDecode

enum UserNetworkServiceError: Error {
    case missingUserInfo
    case missingSub
    case tokenRefreshFailed
    case noRefreshTokenAvailable
}

protocol UserNetworkService: NetworkService {
    func login() async throws -> UserAPIResponse
    func logout() async throws
    func updateUser(firstName: String?, lastName: String?) async throws -> UserAPIResponse
    func getUser() async throws -> UserAPIResponse
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
    
    func getUser() async throws -> UserAPIResponse {
        let credentials = try keychainManager.loadUserCredentials()
        
        return try await withCheckedThrowingContinuation { continuation in
            Auth0
                .authentication()
                .userInfo(withAccessToken: credentials.accessToken)
                .start { result in
                    switch result {
                    case .success(let userInfo):
                        do {
                            let userAPIResponse = try self.convertAuth0UserToAPIResponse(userInfo, accessToken: credentials.accessToken)
                            continuation.resume(returning: userAPIResponse)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
        }
    }
    
    func updateUser(firstName: String?,
                    lastName: String?) async throws -> UserAPIResponse {
        let credentials = try keychainManager.loadUserCredentials()
        let userId = credentials.id
        
        return try await withCheckedThrowingContinuation { continuation in
            var metadata: [String: Any] = [:]
            if let firstName {
                metadata["given_name"] = firstName
            }
            if let lastName {
                metadata["family_name"] = lastName
            }
            Auth0
                .users(token: credentials.accessToken)
                .patch(userId,
                       userMetadata: metadata)
                .start { result in
                    switch result {
                    case .success(let managementObject):
                        do {
                            guard let userInfo = UserInfo(json: managementObject) else {
                                continuation.resume(throwing: UserNetworkServiceError.missingUserInfo)
                                return
                            }
                            let userAPIResponse = try self.convertAuth0UserToAPIResponse(userInfo, accessToken: credentials.accessToken)
                            continuation.resume(returning: userAPIResponse)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
        }
    }
    
    @MainActor
    func logout() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            Auth0
                .webAuth()
                .clearSession { result in
                    switch result {
                    case .success:
                        self.logger.info("Session cleared successfully")
                        Task {
                            continuation.resume(returning: ())
                        }
                    case .failure(let error):
                        self.logger.error("Session error while clearing: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }
        }
    }
    
    @MainActor
    func login() async throws -> UserAPIResponse {
        return try await withCheckedThrowingContinuation { continuation in
            Auth0
                .webAuth()
                .audience("promptshields-api")
                .scope("openid profile email offline_access")
                .useHTTPS()
                .start { result in
                    do {
                        let credentials = try result.get()
                        continuation.resume(with: .success(try credentials.decode()))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
        }
    }
    
    func refreshToken() async throws -> UserAPIResponse {
        return try await TokenRefreshManager.shared.refreshToken()
    }
    
    private func convertAuth0UserToAPIResponse(_ userInfo: UserInfo, accessToken: String) throws -> UserAPIResponse {
        let userId = userInfo.sub
        let email = userInfo.email
        let firstName = userInfo.givenName ?? "n/a"
        let lastName = userInfo.familyName ?? "n/a"
        let photoURL = userInfo.picture?.absoluteString
        
        // Get existing refresh token from stored credentials if available
        let existingRefreshToken = try? keychainManager.loadUserCredentials().refreshToken
        
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
