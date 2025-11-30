import Foundation

// MARK: - Network Error

/// Comprehensive network error type with detailed error information
/// Conforms to Sendable for safe concurrent access
struct NetworkError: Error, Sendable, LocalizedError {
    // MARK: - Properties

    /// Human-readable error message
    let message: String

    /// HTTP status code if available
    let statusCode: Int?

    /// Underlying error if available
    let underlyingError: (any Error)?

    /// Response data if available (for debugging)
    let responseData: Data?

    // MARK: - Initialization

    init(
        message: String,
        statusCode: Int? = nil,
        underlyingError: (any Error)? = nil,
        responseData: Data? = nil
    ) {
        self.message = message
        self.statusCode = statusCode
        self.underlyingError = underlyingError
        self.responseData = responseData
    }

    // MARK: - LocalizedError

    var errorDescription: String? {
        if let statusCode = statusCode {
            return "[\(statusCode)] \(message)"
        }
        return message
    }

    var failureReason: String? {
        underlyingError?.localizedDescription
    }

    // MARK: - Factory Methods

    static func invalidResponse(message: String) -> NetworkError {
        NetworkError(message: message)
    }

    static func httpError(statusCode: Int, data: Data? = nil) -> NetworkError {
        let message = HTTPStatusCode(rawValue: statusCode)?.description ?? "HTTP Error"
        return NetworkError(message: message, statusCode: statusCode, responseData: data)
    }

    static func decodingError(_ error: DecodingError) -> NetworkError {
        let message: String
        switch error {
        case .typeMismatch(let type, let context):
            message = "Type mismatch for \(type): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            message = "Value not found for \(type): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            message = "Key '\(key.stringValue)' not found: \(context.debugDescription)"
        case .dataCorrupted(let context):
            message = "Data corrupted: \(context.debugDescription)"
        @unknown default:
            message = "Unknown decoding error"
        }
        return NetworkError(message: message, underlyingError: error)
    }

    static func connectionError(_ error: any Error) -> NetworkError {
        NetworkError(
            message: "Connection failed: \(error.localizedDescription)",
            underlyingError: error
        )
    }

    // MARK: - Status Checks

    /// Whether the error indicates an authentication failure
    var isUnauthorized: Bool {
        statusCode == 401 || statusCode == 403
    }

    /// Whether the error indicates a client error (4xx)
    var isClientError: Bool {
        guard let code = statusCode else { return false }
        return (400...499).contains(code)
    }

    /// Whether the error indicates a server error (5xx)
    var isServerError: Bool {
        guard let code = statusCode else { return false }
        return (500...599).contains(code)
    }

    /// Whether the error is retryable
    var isRetryable: Bool {
        // Retry on server errors, timeout, or connection issues
        if isServerError { return true }
        if statusCode == 429 { return true } // Rate limited
        if underlyingError is URLError { return true }
        return false
    }
}

// MARK: - HTTP Status Codes

/// Common HTTP status codes with descriptions
enum HTTPStatusCode: Int {
    case ok = 200
    case created = 201
    case noContent = 204
    case badRequest = 400
    case unauthorized = 401
    case forbidden = 403
    case notFound = 404
    case conflict = 409
    case unprocessableEntity = 422
    case tooManyRequests = 429
    case internalServerError = 500
    case badGateway = 502
    case serviceUnavailable = 503
    case gatewayTimeout = 504

    var description: String {
        switch self {
        case .ok: return "OK"
        case .created: return "Created"
        case .noContent: return "No Content"
        case .badRequest: return "Bad Request"
        case .unauthorized: return "Unauthorized"
        case .forbidden: return "Forbidden"
        case .notFound: return "Not Found"
        case .conflict: return "Conflict"
        case .unprocessableEntity: return "Unprocessable Entity"
        case .tooManyRequests: return "Too Many Requests"
        case .internalServerError: return "Internal Server Error"
        case .badGateway: return "Bad Gateway"
        case .serviceUnavailable: return "Service Unavailable"
        case .gatewayTimeout: return "Gateway Timeout"
        }
    }
}
