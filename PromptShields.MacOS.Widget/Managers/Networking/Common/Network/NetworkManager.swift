import Foundation
import os

enum DecodingError: Error {
    case noNeedToDecodeData
}

protocol NetworkManager: Sendable {
    @discardableResult
    func perform(
        request: URLRequest
    ) async throws -> Data
    
    @discardableResult
    func performWithAutoRefresh(
        request: URLRequest
    ) async throws -> Data
}

actor NetworkManagerImpl: NetworkManager {
    // MARK: - Private Properties
    
    private let session: URLSessionProtocol
    private let logger: Logger
    
    static let shared = NetworkManagerImpl()
    
    init(
        session: URLSessionProtocol = URLSession.shared,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!,
            category: String(describing: NetworkManagerImpl.self)
        )
    ) {
        self.session = session
        self.logger = logger
    }
    
    @discardableResult
    func perform(request: URLRequest) async throws -> Data {
        do {
            logger.debug("REQUEST: \(request.httpMethod ?? "") \n request \(request.url?.absoluteString ?? "")")
            let (data, response) = try await session.dataTask(with: request)
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError(message: "Invalid response type")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError(message: "HTTP \(httpResponse.statusCode): Invalid server response", statusCode: httpResponse.statusCode)
            }
            
            // Log response for debugging
            logResponse(data: data)
            return data
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError(message: "Request failed: \(error.localizedDescription)")
        }
    }
    
    @discardableResult
    func performWithAutoRefresh(request: URLRequest) async throws -> Data {
        do {
            return try await perform(request: request)
        } catch let networkError as NetworkError where networkError.isUnauthorized {
            logger.info("Received 401/403 error, attempting token refresh...")
            
            // Attempt to refresh the token
            do {
                let refreshedCredentials = try await TokenRefreshManager.shared.refreshToken()
                
                // Save refreshed credentials
                let keychainManager = KeychainManagerImpl.shared
                try keychainManager.saveUserCredentials(userCredentials: refreshedCredentials)
                
                // Retry the original request with new token
                var retryRequest = request
                if let authHeader = try? keychainManager.authorizationHeader {
                    for (key, value) in authHeader {
                        retryRequest.setValue(value, forHTTPHeaderField: key)
                    }
                }
                
                logger.info("Token refreshed successfully, retrying request...")
                return try await perform(request: retryRequest)
            } catch {
                logger.error("Token refresh failed: \(error.localizedDescription)")
                
                // If refresh fails, log out the user
                Task { @MainActor in
                    await handleLogoutAfterFailedRefresh()
                }
                
                throw networkError // Throw original error
            }
        }
    }
    
    @MainActor
    private func handleLogoutAfterFailedRefresh() async {
        logger.error("Token refresh failed, posting notification for logout...")
        
        // Post notification that token refresh failed - the UI layer will handle logout
        NotificationCenter.default.post(name: .tokenRefreshFailed, object: nil)
    }
    
    private func logResponse(data: Data) {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers)
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            let response = String(decoding: jsonData, as: UTF8.self)
            logger.debug("Response: \(response)")
        } catch {
            let response = String(decoding: data, as: UTF8.self)
            logger.error("JSON data malformed: \(response)")
            logger.error("Failed to log response: \(error.localizedDescription)")
        }
    }
}
