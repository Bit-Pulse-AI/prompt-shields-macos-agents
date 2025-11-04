import Foundation
import AppKit

// MARK: - AXUIElement Hashable Conformance

/// A Sendable identifier for AXUIElement with graceful error handling
/// A Sendable identifier for AXUIElement with graceful error handling
struct AXElementID: Sendable, Hashable {
    private let pointerValue: UInt

    init(_ element: AXUIElement) {
        self.pointerValue = UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque())
    }

    /// Check if this element ID matches the given element
    /// - Parameter element: The element to compare against
    /// - Returns: True if they represent the same element
    func matches(_ element: AXUIElement) -> Bool {
        let elementPointer = UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque())
        return pointerValue == elementPointer
    }

    /// Get the pointer value for debugging
    var debugPointerValue: UInt {
        return pointerValue
    }
}

extension AXUIElement: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        // Use the underlying pointer value for hashing
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }

    public static func == (lhs: AXUIElement, rhs: AXUIElement) -> Bool {
        // Compare the underlying pointer values
        return Unmanaged.passUnretained(lhs).toOpaque() == Unmanaged.passUnretained(rhs).toOpaque()
    }
}

/// Safe wrapper for AXUIElement operations to prevent memory leaks
final class AXUIElementSafeWrapper {
    // MARK: - Safe Attribute Access

    /// Safely get an attribute value from an AXUIElement
    /// - Parameters:
    ///   - element: The AXUIElement to query
    ///   - attribute: The attribute to get
    /// - Returns: The attribute value or nil if failed
    static func getAttributeValue(from element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        guard result == .success else {
            return nil
        }

        return value
    }

    /// Safely get children from an AXUIElement with validation
    /// - Parameter element: The AXUIElement to get children from
    /// - Returns: Array of child AXUIElements or empty array if failed
    static func getChildren(from element: AXUIElement) -> [AXUIElement] {
        // First validate the element is still valid
        guard isValidElement(element) else {
            return []
        }

        guard let childrenRef = getAttributeValue(from: element, attribute: kAXChildrenAttribute),
              let children = childrenRef as? [AXUIElement] else {
            return []
        }

        // Filter out invalid children
        return children.filter { isValidElement($0) }
    }

    /// Safely get a parameterized attribute value
    /// - Parameters:
    ///   - element: The AXUIElement to query
    ///   - attribute: The parameterized attribute to get
    ///   - parameter: The parameter value
    /// - Returns: The attribute value or nil if failed
    static func getParameterizedAttributeValue(
        from element: AXUIElement,
        attribute: String,
        parameter: CFTypeRef
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute as CFString,
            parameter,
            &value
        )

        guard result == .success else {
            return nil
        }

        return value
    }

    // MARK: - Safe Element Creation

    /// Safely create an AXUIElement for an application
    /// - Parameter processIdentifier: The process ID of the application
    /// - Returns: The AXUIElement or nil if failed
    static func createApplicationElement(processIdentifier: pid_t) -> AXUIElement? {
        let element = AXUIElementCreateApplication(processIdentifier)

        // Validate the element
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)

        guard result == .success && pid == processIdentifier else {
            return nil
        }

        return element
    }

    /// Safely create a system-wide AXUIElement
    /// - Returns: The system-wide AXUIElement
    static func createSystemWideElement() -> AXUIElement {
        return AXUIElementCreateSystemWide()
    }

    // MARK: - Safe Element Validation

    /// Check if an AXUIElement is still valid
    /// - Parameter element: The AXUIElement to validate
    /// - Returns: True if the element is valid
    static func isValidElement(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        return result == .success && pid > 0
    }

    /// Check if an AXUIElement belongs to a specific application
    /// - Parameters:
    ///   - element: The AXUIElement to check
    ///   - processIdentifier: The expected process ID
    /// - Returns: True if the element belongs to the specified application
    static func elementBelongsToApplication(_ element: AXUIElement, processIdentifier: pid_t) -> Bool {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        return result == .success && pid == processIdentifier
    }

    // MARK: - Safe Element Traversal

    /// Safely traverse an AXUIElement tree with memory management
    /// - Parameters:
    ///   - element: The root AXUIElement
    ///   - maxDepth: Maximum depth to traverse
    ///   - visitor: Closure called for each element
    static func traverseElementTree(
        _ element: AXUIElement,
        maxDepth: Int = 10,
        visitor: @escaping (AXUIElement, Int) -> Bool
    ) {
        traverseElementRecursive(element, depth: 0, maxDepth: maxDepth, visitor: visitor)
    }

    private static func traverseElementRecursive(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        visitor: @escaping (AXUIElement, Int) -> Bool
    ) {
        guard depth < maxDepth,
              isValidElement(element),
              visitor(element, depth) else {
            return
        }

        // Get children safely
        let children = getChildren(from: element)

        for child in children {
            traverseElementRecursive(child, depth: depth + 1, maxDepth: maxDepth, visitor: visitor)
        }
    }

    // MARK: - Safe Text Extraction

    /// Safely get selected text from an AXUIElement
    /// - Parameter element: The AXUIElement to get selected text from
    /// - Returns: The selected text or nil if no text is selected
    static func getSelectedText(from element: AXUIElement) -> String? {
        guard isValidElement(element) else {
            return nil
        }

        // First check if there's a selection range
        guard let selectedRangeValue = getAttributeValue(from: element, attribute: kAXSelectedTextRangeAttribute) else {
            return nil
        }

        // Check if the selection range has length > 0
        var cfRange = CFRange()
        guard AXValueGetValue(selectedRangeValue as! AXValue, .cfRange, &cfRange),
              cfRange.length > 0 else {
            return nil
        }

        // Get the selected text
        guard let selectedTextValue = getAttributeValue(from: element, attribute: kAXSelectedTextAttribute),
              let selectedText = selectedTextValue as? String,
              !selectedText.isEmpty else {
            return nil
        }

        return selectedText
    }

    /// Safely extract text from an AXUIElement
    /// - Parameter element: The AXUIElement to extract text from
    /// - Returns: The extracted text or empty string (prioritizes selected text if available)
    static func extractText(from element: AXUIElement) -> String {
        guard isValidElement(element) else {
            return ""
        }

        // First check for selected text
        if let selectedText = getSelectedText(from: element) {
            return selectedText
        }

        var collectedText: [String] = []

        // Check common text attributes
        let textAttributes = [
            kAXValueAttribute,
            kAXTitleAttribute,
            kAXLabelValueAttribute,
            kAXDescriptionAttribute,
            kAXPlaceholderValueAttribute
        ]

        for attribute in textAttributes {
            if let value = getAttributeValue(from: element, attribute: attribute) {
                if let string = value as? String, !string.isEmpty {
                    collectedText.append(string)
                } else if let attributedString = value as? NSAttributedString, !attributedString.string.isEmpty {
                    collectedText.append(attributedString.string)
                }
            }
        }

        return collectedText.joined(separator: " ")
    }

    // MARK: - Memory Management Utilities

    /// Perform an operation with automatic memory cleanup
    /// - Parameter operation: The operation to perform
    /// - Returns: The result of the operation
    static func withMemoryCleanup<T>(_ operation: () -> T) -> T {
        return autoreleasepool {
            operation()
        }
    }
}
