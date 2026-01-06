import Foundation

enum AppServiceErrors: LocalizedError {
    case loginUserError(Error?)
    case missingEmail
    case failedAuthentication
}
