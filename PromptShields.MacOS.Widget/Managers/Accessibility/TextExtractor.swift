import AppKit

final class TextExtractor: Sendable {
    func getAllText(from element: AXUIElement) -> String {
        // Validate the element first
        guard isValidElement(element) else {
            return ""
        }
        
        var collectedText: [String] = []
            
        // Attributes to check for "text-like" values
        let attributesToCheck: [String] = [
            kAXValueAttribute,          // Editable fields, static text
            kAXTitleAttribute,          // Buttons, windows, group boxes
            kAXLabelValueAttribute,     // Some labels
            kAXDescriptionAttribute,    // Images, icons, etc.
            kAXPlaceholderValueAttribute // Placeholder text in text fields
        ]
            
        // Check each attribute for a string or attributed string
        for attr in attributesToCheck {
            var value: AnyObject?
            let error = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
                
            if error == .success, let value = value {
                // Safely handle string values
                if let str = value as? String, !str.isEmpty {
                    collectedText.append(str)
                }
                // Safely handle attributed string values
                if let attrStr = value as? NSAttributedString, !attrStr.string.isEmpty {
                    collectedText.append(attrStr.string)
                }
            }
        }
            
        // Recursively check children with proper error handling
        var children: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let childArray = children as? [AXUIElement] {
            for child in childArray {
                // Validate child element before processing
                guard isValidElement(child) else { continue }
                
                let childText = getAllText(from: child)
                if !childText.isEmpty {
                    collectedText.append(childText)
                }
            }
        }
            
        // Return combined text
        return collectedText.joined(separator: " ")
    }
    
    // MARK: - Helper Methods
    
    /// Validates if an AXUIElement is still valid and accessible
    private func isValidElement(_ element: AXUIElement) -> Bool {
        // Check if the element is still valid by trying to get a basic attribute
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        return result == .success && pid > 0
    }
    
    /// Safe version of getAllText with error handling
    func getAllTextSafely(from element: AXUIElement) -> Result<String, AccessibilityError> {
        // Validate the element first
        guard isValidElement(element) else {
            return .failure(.invalidUIElement)
        }
        
        let text = getAllText(from: element)
        return .success(text)
    }
}
