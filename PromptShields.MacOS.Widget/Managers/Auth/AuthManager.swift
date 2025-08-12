import SwiftUI
import Auth0
import JWTDecode
import SwiftData
import os

/// Authentication errors that can occur during the authentication process
enum AuthError: Error, LocalizedError {
    case missingLocalId
    case currentUserNotFound
    case missingTokenEmail
    
    var errorDescription: String? {
        switch self {
        case .missingLocalId:
            return "Local user ID is missing"
        case .currentUserNotFound:
            return "Current user not found in database"
        case .missingTokenEmail:
            return "Email not found in authentication token"
        }
    }
}
