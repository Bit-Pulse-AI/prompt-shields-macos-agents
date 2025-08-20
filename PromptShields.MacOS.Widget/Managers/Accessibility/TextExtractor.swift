import AppKit

final class TextExtractor: Sendable {
    func getAllText(from element: AXUIElement) -> String {
        return AXUIElementSafeWrapper.withMemoryCleanup {
            // Validate the element first
            guard AXUIElementSafeWrapper.isValidElement(element) else {
                return ""
            }
            
            var collectedText: [String] = []
                
            // Use safe wrapper for text extraction
            let text = AXUIElementSafeWrapper.extractText(from: element)
            if !text.isEmpty {
                collectedText.append(text)
            }
                
            // Recursively check children with safe wrapper
            let children = AXUIElementSafeWrapper.getChildren(from: element)
            for child in children {
                // Validate child element before processing
                guard AXUIElementSafeWrapper.isValidElement(child) else { continue }
                
                let childText = getAllText(from: child)
                if !childText.isEmpty {
                    collectedText.append(childText)
                }
            }
                
            // Return combined text
            return collectedText.joined(separator: " ")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Validates if an AXUIElement is still valid and accessible
    private func isValidElement(_ element: AXUIElement) -> Bool {
        return AXUIElementSafeWrapper.isValidElement(element)
    }
    
    /// Safe version of getAllText with error handling
    func getAllTextSafely(from element: AXUIElement) -> Result<String, AccessibilityError> {
        let text: String? = AXUIElementSafeWrapper.withMemoryCleanup {
            // Validate the element first
            guard AXUIElementSafeWrapper.isValidElement(element) else {
                return nil
            }
            
            let text = getAllText(from: element)
            return text
        }
        guard let text else {
            return .failure(.invalidUIElement)
        }
        return .success(text)
    }
}
