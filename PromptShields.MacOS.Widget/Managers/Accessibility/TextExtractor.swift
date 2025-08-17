import AppKit

final class TextExtractor: Sendable {
    func getAllText(from element: AXUIElement) -> String {
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
                    if let str = value as? String, !str.isEmpty {
                        collectedText.append(str)
                    }
                    if let attrStr = value as? NSAttributedString, !attrStr.string.isEmpty {
                        collectedText.append(attrStr.string)
                    }
                }
            }
            
            // Recursively check children
            var children: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let childArray = children as? [AXUIElement] {
                for child in childArray {
                    let childText = getAllText(from: child)
                    if !childText.isEmpty {
                        collectedText.append(childText)
                    }
                }
            }
            
            // Return combined text
            return collectedText.joined(separator: " ")
    }
}
