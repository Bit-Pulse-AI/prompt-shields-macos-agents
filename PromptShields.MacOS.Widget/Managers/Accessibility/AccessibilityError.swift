import AppKit

// MARK: - Accessibility Errors
enum AccessibilityError: Error, LocalizedError {
    case noActiveTextField
    case noAccessibilityPermissions
    case accessibilityAPIDisabled
    case invalidUIElement
    case unknownError(AXError)
    case failedToGetFocusedElement
    case failedToGetAttribute(String)
    case failedToGetFrame
    case failedToGetApplicationInfo
    case failedToExtractText
    case failedToInjectText
    case timeout

    var errorDescription: String? {
        switch self {
        case .noActiveTextField:
            return "No active text field found"
        case .noAccessibilityPermissions:
            return "Accessibility permissions not granted. Please enable in System Settings > Privacy & Security > Accessibility"
        case .accessibilityAPIDisabled:
            return "Accessibility API is disabled"
        case .invalidUIElement:
            return "Invalid UI element"
        case .unknownError(let error):
            return "Unknown accessibility error: \(error)"
        case .failedToGetFocusedElement:
            return "Failed to get focused element"
        case .failedToGetAttribute(let attribute):
            return "Failed to get attribute: \(attribute)"
        case .failedToGetFrame:
            return "Failed to get element position"
        case .failedToGetApplicationInfo:
            return "Failed to get application information"
        case .failedToExtractText:
            return "Failed to extract text from element"
        case .failedToInjectText:
            return "Failed to inject text into element"
        case .timeout:
            return "Operation timed out"
        }
    }
}
