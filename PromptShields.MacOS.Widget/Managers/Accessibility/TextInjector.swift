import AppKit

actor TextInjector {
    // Shared instance to prevent unnecessary creation
    static let shared = TextInjector()
    
    private init() {} // Private initializer to enforce singleton pattern
    
    func injectText(_ text: String, into element: AXUIElement) async throws {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        
        guard result == .success else {
            throw AccessibilityError.failedToInjectText
        }
    }
}
