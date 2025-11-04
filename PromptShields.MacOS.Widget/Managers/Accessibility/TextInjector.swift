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

    /// Inject text into an element, handling both selected text replacement and full text replacement
    /// - Parameters:
    ///   - text: The text to inject
    ///   - element: The AXUIElement to inject text into
    ///   - isSelectedText: Whether the original text came from a selection (true) or full element (false)
    func injectText(_ text: String, into element: AXUIElement, isSelectedText: Bool) async throws {
        if isSelectedText {
            // For selected text, we need to replace only the selected range
            try await replaceSelectedText(with: text, in: element)
        } else {
            // For full element text, replace the entire value
            try await injectText(text, into: element)
        }
    }

    /// Replace the currently selected text in an element with new text
    /// - Parameters:
    ///   - text: The replacement text
    ///   - element: The AXUIElement containing the selection
    private func replaceSelectedText(with text: String, in element: AXUIElement) async throws {
        // Get the current selection range
        guard let selectedRangeValue = AXUIElementSafeWrapper.getAttributeValue(from: element, attribute: kAXSelectedTextRangeAttribute) else {
            throw AccessibilityError.failedToInjectText
        }

        // Extract the range
        var cfRange = CFRange()
        guard AXValueGetValue(selectedRangeValue as! AXValue, .cfRange, &cfRange) else {
            throw AccessibilityError.failedToInjectText
        }

        // Get the current full text
        guard let currentValue = AXUIElementSafeWrapper.getAttributeValue(from: element, attribute: kAXValueAttribute),
              let currentText = currentValue as? String else {
            throw AccessibilityError.failedToInjectText
        }

        // Replace the selected portion with new text
        let startIndex = currentText.index(currentText.startIndex, offsetBy: cfRange.location)
        let endIndex = currentText.index(startIndex, offsetBy: cfRange.length)
        let range = startIndex..<endIndex

        var newText = currentText
        newText.replaceSubrange(range, with: text)

        // Set the new text
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newText as CFTypeRef)
        guard result == .success else {
            throw AccessibilityError.failedToInjectText
        }

        // Update the selection to highlight the newly inserted text
        var newRange = CFRange(location: cfRange.location, length: text.count)
        let newRangeValue = AXValueCreate(.cfRange, &newRange)

        if let rangeValue = newRangeValue {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }
    }
}
