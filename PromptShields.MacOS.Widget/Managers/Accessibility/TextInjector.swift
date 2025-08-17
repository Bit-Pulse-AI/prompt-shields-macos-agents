import AppKit

actor TextInjector {
    func injectText(_ text: String, into element: AXUIElement) async throws {
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        
        guard result == .success else {
            throw AccessibilityError.failedToInjectText
        }
    }
}
