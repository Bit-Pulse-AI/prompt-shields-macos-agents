import AppKit
import os

// MARK: - AXElement Registry

/// MainActor-isolated registry that maintains references to AXUIElements
/// and allows lookup by AXElementID.
///
/// This solves the problem of AXUIElement not being Sendable:
/// - ElementInfo stores only the Sendable AXElementID
/// - When you need the actual element, look it up in this registry
/// - The registry is MainActor-isolated, ensuring thread safety
@MainActor
final class AXElementRegistry {
    // MARK: - Singleton

    static let shared = AXElementRegistry()

    // MARK: - Properties

    /// Maps element IDs to their AXUIElements
    private var elements: [AXElementID: AXUIElement] = [:]

    /// Logger for registry operations
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "AXElementRegistry"
    )

    /// Maximum number of elements to keep in registry
    private let maxElements = 10

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Registers an element and returns its ID
    /// - Parameter element: The AXUIElement to register
    /// - Returns: The AXElementID for the registered element
    @discardableResult
    func register(_ element: AXUIElement) -> AXElementID {
        let elementId = AXElementID(element)

        // Clean up if we have too many elements
        if elements.count >= maxElements {
            cleanupInvalidElements()
        }

        elements[elementId] = element
        logger.debug("Registered element: \(elementId.debugPointerValue)")

        return elementId
    }

    /// Looks up an element by its ID
    /// - Parameter id: The AXElementID to look up
    /// - Returns: The AXUIElement if found and still valid, nil otherwise
    func lookup(_ id: AXElementID) -> AXUIElement? {
        guard let element = elements[id] else {
            logger.debug("Element not found in registry: \(id.debugPointerValue)")
            return nil
        }

        // Verify the element is still valid
        guard AXUIElementSafeWrapper.isValidElement(element) else {
            logger.debug("Element is no longer valid, removing: \(id.debugPointerValue)")
            elements.removeValue(forKey: id)
            return nil
        }

        return element
    }

    /// Looks up an element by its ID, throwing if not found
    /// - Parameter id: The AXElementID to look up
    /// - Returns: The AXUIElement
    /// - Throws: AccessibilityError.invalidUIElement if not found or invalid
    func lookupOrThrow(_ id: AXElementID) throws -> AXUIElement {
        guard let element = lookup(id) else {
            throw AccessibilityError.invalidUIElement
        }
        return element
    }

    /// Removes an element from the registry
    /// - Parameter id: The AXElementID to remove
    func unregister(_ id: AXElementID) {
        elements.removeValue(forKey: id)
        logger.debug("Unregistered element: \(id.debugPointerValue)")
    }

    /// Removes all elements from the registry
    func clear() {
        elements.removeAll()
        logger.debug("Cleared all elements from registry")
    }

    /// Updates the current element, replacing any existing one
    /// - Parameter element: The new current AXUIElement
    /// - Returns: The AXElementID for the element
    @discardableResult
    func updateCurrent(_ element: AXUIElement) -> AXElementID {
        // Remove all existing elements (we only track the current one)
        elements.removeAll()
        return register(element)
    }

    /// Checks if an element ID is registered and valid
    /// - Parameter id: The AXElementID to check
    /// - Returns: true if the element is registered and valid
    func isValid(_ id: AXElementID) -> Bool {
        lookup(id) != nil
    }

    // MARK: - Private Methods

    /// Removes invalid elements from the registry
    private func cleanupInvalidElements() {
        let invalidIds = elements.keys.filter { id in
            guard let element = elements[id] else { return true }
            return !AXUIElementSafeWrapper.isValidElement(element)
        }

        for id in invalidIds {
            elements.removeValue(forKey: id)
        }

        logger.debug("Cleaned up \(invalidIds.count) invalid elements")
    }
}

// MARK: - Convenience Extensions

extension AXElementID {
    /// Looks up the AXUIElement for this ID in the shared registry
    /// Must be called on MainActor
    @MainActor
    var element: AXUIElement? {
        AXElementRegistry.shared.lookup(self)
    }

    /// Looks up the AXUIElement for this ID, throwing if not found
    /// Must be called on MainActor
    @MainActor
    func getElement() throws -> AXUIElement {
        try AXElementRegistry.shared.lookupOrThrow(self)
    }
}

// MARK: - Optional AXElementID Extension

extension Optional where Wrapped == AXElementID {
    /// Looks up the AXUIElement for this optional ID
    /// Must be called on MainActor
    @MainActor
    var element: AXUIElement? {
        self?.element
    }
}
