import AppKit

actor TextInjector {
    func injectText(_ text: String, into textField: ElementInfo) async throws {
//        let result = AXUIElementSetAttributeValue(textField.element, kAXValueAttribute as CFString, text as CFTypeRef)
//        
//        guard result == .success else {
            throw AccessibilityError.failedToInjectText
//        }
    }
}
