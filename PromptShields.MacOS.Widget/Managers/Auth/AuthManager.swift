import SwiftUI
import SwiftData
import os

/// Notification for token refresh failures that should trigger logout
extension Notification.Name {
    static let tokenRefreshFailed = Notification.Name("tokenRefreshFailed")
}

/// Authentication errors that can occur during the authentication process
enum AuthError: Error, LocalizedError {
    case missingLocalId
    case currentUserNotFound
    case missingTokenEmail
    case tokenRefreshFailed
    case noRefreshTokenAvailable
    case tokenExpired
    case unauthorizedAccess

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
        }
    }
}
