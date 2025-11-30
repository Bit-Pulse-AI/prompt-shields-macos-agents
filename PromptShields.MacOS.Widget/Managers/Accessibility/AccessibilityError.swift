import Foundation

// MARK: - Accessibility Error

/// Errors that can occur during accessibility operations
/// Conforms to Sendable for safe concurrent access in Swift 6
enum AccessibilityError: Error, Sendable, LocalizedError {
    
    // MARK: - Cases
    
    /// Failed to get the frame of an element
    case failedToGetFrame
    
    /// Failed to get application information
    case failedToGetApplicationInfo
    
    /// Failed to inject text into an element
    case failedToInjectText
    
    /// Failed to get the focused element
    case failedToGetFocusedElement
    
    /// The UI element is invalid or no longer exists
    case invalidUIElement
    
    /// Accessibility permissions are not granted
    case permissionsNotGranted
    
    /// Operation timed out
    case timeout
    
    /// The element does not support text operations
    case textNotSupported
    
    /// Failed to get selected text range
    case failedToGetSelectionRange
    
    /// The process is not trusted for accessibility
    case processNotTrusted
    
    // MARK: - LocalizedError
    
    var errorDescription: String? {
        switch self {
        case .failedToGetFrame:
            return "Failed to get element frame"
        case .failedToGetApplicationInfo:
            return "Failed to get application information"
        case .failedToInjectText:
            return "Failed to inject text into element"
        case .failedToGetFocusedElement:
            return "Failed to get focused element"
        case .invalidUIElement:
            return "UI element is invalid or no longer exists"
        case .permissionsNotGranted:
            return "Accessibility permissions are not granted"
        case .timeout:
            return "Operation timed out"
        case .textNotSupported:
            return "Element does not support text operations"
        case .failedToGetSelectionRange:
            return "Failed to get text selection range"
        case .processNotTrusted:
            return "Process is not trusted for accessibility"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionsNotGranted, .processNotTrusted:
            return "Please grant accessibility permissions in System Preferences > Security & Privacy > Privacy > Accessibility"
        case .timeout:
            return "Try the operation again"
        case .invalidUIElement:
            return "The element may have been removed. Try selecting a different element."
        default:
            return nil
        }
    }
}
