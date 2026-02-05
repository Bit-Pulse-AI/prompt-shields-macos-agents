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
    @MainActor
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
    @MainActor
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
        AXUIElementCreateSystemWide()
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

    @MainActor
    static func traverseElementTree(
        _ element: AXUIElement,
        maxDepth: Int = 10,
        visitor: @escaping (AXUIElement, Int) -> Bool
    ) {
        traverseElementRecursive(element, depth: 0, maxDepth: maxDepth, visitor: visitor)
    }

    @MainActor
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

        let children = getChildren(from: element)

        for child in children {
            traverseElementRecursive(child, depth: depth + 1, maxDepth: maxDepth, visitor: visitor)
        }
    }

    // MARK: - Safe Text Extraction

    /// Safely get selected text from an AXUIElement
    /// - Parameter element: The AXUIElement to get selected text from
    /// - Returns: The selected text or nil if no text is selected
    @MainActor
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
    @MainActor
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

    // MARK: - Role Detection

    /// Common editable text roles in accessibility API
    private static let editableRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField"
    ]

    /// Web content roles that may contain editable elements
    private static let webContentRoles: Set<String> = [
        "AXWebArea",
        "AXGroup"
    ]

    /// Browser bundle identifiers
    private static let browserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "org.mozilla.firefox",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser" // Arc
    ]

    /// Gets the role of an AXUIElement
    /// - Parameter element: The element to get the role from
    /// - Returns: The role string or nil if unavailable
    @MainActor
    static func getRole(from element: AXUIElement) -> String? {
        guard let roleRef = getAttributeValue(from: element, attribute: kAXRoleAttribute) else {
            return nil
        }
        return roleRef as? String
    }

    /// Gets the subrole of an AXUIElement
    /// - Parameter element: The element to get the subrole from
    /// - Returns: The subrole string or nil if unavailable
    @MainActor
    static func getSubrole(from element: AXUIElement) -> String? {
        guard let subroleRef = getAttributeValue(from: element, attribute: kAXSubroleAttribute) else {
            return nil
        }
        return subroleRef as? String
    }

    static func asAXUIElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    /// Checks if an element is editable
    /// - Parameter element: The element to check
    /// - Returns: True if the element is editable
    @MainActor
    static func isEditable(_ element: AXUIElement) -> Bool {
        // Check explicit editable attribute (used by web content)
        if let editableRef = getAttributeValue(from: element, attribute: "AXEditable"),
           let editable = editableRef as? Bool, editable {
            return true
        }

        // Check if element has an editable role
        if let role = getRole(from: element), editableRoles.contains(role) {
            return true
        }

        // Check for editable ancestor (contenteditable in web)
        if let editableAncestorRef = getAttributeValue(from: element, attribute: "AXEditableAncestor"),
           let _ = asAXUIElement(editableAncestorRef) {
            return true
        }

        return false
    }

    /// Checks if an element is a text input element (editable or has text value support)
    /// - Parameter element: The element to check
    /// - Returns: True if the element supports text input
    @MainActor
    static func isTextInputElement(_ element: AXUIElement) -> Bool {
        // Check if explicitly editable
        if isEditable(element) {
            return true
        }

        // Check if it has a value attribute that can potentially be modified
        guard let role = getRole(from: element) else {
            return false
        }

        // Standard text input roles
        if editableRoles.contains(role) {
            return true
        }

        // Check for text-related attributes that suggest editability
        if getAttributeValue(from: element, attribute: kAXValueAttribute) != nil ||
           getAttributeValue(from: element, attribute: kAXSelectedTextAttribute) != nil ||
           getAttributeValue(from: element, attribute: kAXSelectedTextRangeAttribute) != nil {
            // Has text-related attributes, verify it's a text element
            let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXStaticText", "AXGroup"]
            if textRoles.contains(role) {
                return true
            }
        }

        return false
    }

    /// Checks if an application is a web browser
    /// - Parameter bundleId: The bundle identifier of the application
    /// - Returns: True if the application is a known browser
    static func isBrowser(bundleId: String) -> Bool {
        return browserBundleIds.contains(bundleId)
    }

    /// Checks if an element is web content (AXWebArea)
    /// - Parameter element: The element to check
    /// - Returns: True if the element is or is within web content
    @MainActor
    static func isWebContent(_ element: AXUIElement) -> Bool {
        if let role = getRole(from: element), role == "AXWebArea" {
            return true
        }

        // Check parent chain for web area
        var currentElement: AXUIElement? = element
        var depth = 0
        let maxDepth = 15

        while let current = currentElement, depth < maxDepth {
            if let role = getRole(from: current), role == "AXWebArea" {
                return true
            }

            guard let parentRef = getAttributeValue(from: current, attribute: kAXParentAttribute),
                  let parent = asAXUIElement(parentRef) else {
                break
            }
            currentElement = parent
            depth += 1
        }

        return false
    }

    /// Finds the first editable element in a web content area
    /// This traverses the accessibility tree to find text inputs within web content
    /// - Parameters:
    ///   - element: The starting element (typically focused element or web area)
    ///   - maxDepth: Maximum depth to traverse
    /// - Returns: The first editable element found, or nil
    @MainActor
    static func findEditableElementInWebContent(_ element: AXUIElement, maxDepth: Int = 25) -> AXUIElement? {
        // If this element is editable, return it
        if isEditable(element) {
            return element
        }

        // Check if current element has focus and is a text element
        if let role = getRole(from: element) {
            // In browsers, focused text fields may have AXGroup role with AXEditable or focused text attributes
            if role == "AXGroup" || role == "AXTextField" || role == "AXTextArea" {
                // Check for focused state
                if let focusedRef = getAttributeValue(from: element, attribute: kAXFocusedAttribute),
                   let focused = focusedRef as? Bool, focused {
                    // If it has text-related attributes, it's likely our target
                    if getAttributeValue(from: element, attribute: kAXValueAttribute) != nil ||
                       getAttributeValue(from: element, attribute: kAXSelectedTextRangeAttribute) != nil {
                        return element
                    }
                }
            }
        }

        return findEditableRecursive(element, depth: 0, maxDepth: maxDepth)
    }

    @MainActor
    private static func findEditableRecursive(_ element: AXUIElement, depth: Int, maxDepth: Int) -> AXUIElement? {
        guard depth < maxDepth, isValidElement(element) else { return nil }

        // Check if this element is editable and focused
        if isEditable(element) {
            if let focusedRef = getAttributeValue(from: element, attribute: kAXFocusedAttribute),
               let focused = focusedRef as? Bool, focused {
                return element
            }
        }

        // Check children
        let children = getChildren(from: element)
        for child in children {
            // First check if child is focused - browsers often report the focused element directly
            if let focusedRef = getAttributeValue(from: child, attribute: kAXFocusedAttribute),
               let focused = focusedRef as? Bool, focused {
                if isEditable(child) || isTextInputElement(child) {
                    return child
                }
            }

            // Recurse into child
            if let found = findEditableRecursive(child, depth: depth + 1, maxDepth: maxDepth) {
                return found
            }
        }

        return nil
    }

    /// Gets the focused element within web content, including nested iframes and shadow DOM
    /// - Parameter webArea: The web area element to search within
    /// - Returns: The focused editable element, or nil if not found
    @MainActor
    static func getFocusedElementInWebContent(_ webArea: AXUIElement) -> AXUIElement? {
        // First try the direct focused element approach
        if let focusedRef = getAttributeValue(from: webArea, attribute: kAXFocusedUIElementAttribute) {
            let focused = focusedRef as! AXUIElement
            if isValidElement(focused) {
                // Check if the focused element is editable or is a text input
                if isEditable(focused) || isTextInputElement(focused) {
                    return focused
                }
                // The focused element might be a container, search within it
                if let editable = findEditableElementInWebContent(focused, maxDepth: 10) {
                    return editable
                }
            }
        }

        // Fall back to searching the entire web area
        return findEditableElementInWebContent(webArea, maxDepth: 25)
    }
}
