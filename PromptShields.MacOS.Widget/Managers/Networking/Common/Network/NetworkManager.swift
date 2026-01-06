import Foundation
import os

// MARK: - Decoding Error

enum DataDecodingError: Error {
    case noNeedToDecodeData
    case emptyResponse
}

// MARK: - Network Manager Protocol

/// Protocol for network operations
/// Follows Interface Segregation Principle - focused on network operations only
protocol NetworkManager: Sendable {
    /// Performs a network request
    /// - Parameter request: The URLRequest to perform
    /// - Returns: The response data
    /// - Throws: NetworkError if the request fails
    @discardableResult
    func perform(request: URLRequest) async throws -> Data

    /// Performs a network request with automatic token refresh on 401/403
    /// - Parameter request: The URLRequest to perform
    /// - Returns: The response data
    /// - Throws: NetworkError if the request fails
    @discardableResult
    func performWithAutoRefresh(request: URLRequest) async throws -> Data
}

// MARK: - Network Manager Implementation

/// Thread-safe network manager implementation using actor isolation
actor NetworkManagerImpl: NetworkManager {
    // MARK: - Properties

    private let session: URLSessionProtocol
    private let logger: Logger
    private let maxRetryAttempts: Int
    private let retryDelay: Duration

    // MARK: - Singleton

    static let shared = NetworkManagerImpl()

    // MARK: - Initialization

    init(
        session: URLSessionProtocol = URLSession.shared,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
            category: "NetworkManager"
        ),
        maxRetryAttempts: Int = 3,
        retryDelay: Duration = .milliseconds(500)
    ) {
        self.session = session
        self.logger = logger
        self.maxRetryAttempts = maxRetryAttempts
        self.retryDelay = retryDelay
    }

    // MARK: - Public Methods

    @discardableResult
    func perform(request: URLRequest) async throws -> Data {
        let requestId = UUID().uuidString.prefix(8)

        logger.debug("[\(requestId)] \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "unknown")")

        do {
            let (data, response) = try await session.dataTask(with: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError(message: "Invalid response type")
            }

            // Log response
            logResponse(requestId: String(requestId), statusCode: httpResponse.statusCode, data: data)

            // Check for HTTP errors
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
            }

            return data
        } catch let error as NetworkError {
            logger.debug("[\(requestId)] Network error: \(error.message)")
            throw error
        } catch {
            logger.debug("[\(requestId)] Request failed: \(error.localizedDescription)")
            throw NetworkError.connectionError(error)
        }
    }

    @discardableResult
    func performWithAutoRefresh(request: URLRequest) async throws -> Data {
        do {
            return try await perform(request: request)
        } catch let networkError as NetworkError where networkError.isUnauthorized {
            logger.debug("Received \(networkError.statusCode ?? 401) error, attempting token refresh...")

            do {
                // Attempt to refresh the token
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

                logger.debug("Token refreshed successfully, retrying request...")
                return try await perform(request: retryRequest)
            } catch {
                logger.debug("Token refresh failed: \(error.localizedDescription)")

                // Post notification for logout on main thread
                await handleLogoutAfterFailedRefresh()

                throw networkError
            }
        }
    }

    // MARK: - Private Methods

    @MainActor
    private func handleLogoutAfterFailedRefresh() {
        logger.debug("Token refresh failed, posting notification for logout...")
        NotificationCenter.default.post(name: .tokenRefreshFailed, object: nil)
    }

    private func logResponse(requestId: String, statusCode: Int, data: Data) {
        #if DEBUG
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            let response = String(decoding: jsonData, as: UTF8.self)
            logger.debug("[\(requestId)] Response (\(statusCode)): \(response.prefix(500))")
        } catch {
            let response = String(decoding: data, as: UTF8.self)
            logger.debug("[\(requestId)] Response (\(statusCode)): \(response.prefix(500))")
        }
        #else
        logger.debug("[\(requestId)] Response: \(statusCode)")
        #endif
    }
}
