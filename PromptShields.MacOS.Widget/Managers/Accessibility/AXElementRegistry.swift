import AppKit
import os

// MARK: - AXElement Registry

/// MainActor-isolated registry for tracking interaction state.
/// Simplified to focus on locking/unlocking during user interactions.
///
/// Note: The actual AXUIElement is now acquired fresh at injection time
/// via TextInjectionService, so we no longer need to store element references.
@MainActor
final class AXElementRegistry {
    // MARK: - Singleton

    static let shared = AXElementRegistry()

    // MARK: - Properties

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "AXElementRegistry"
    )

    /// When true, indicates user is interacting with action menu
    private var isLocked = false

    /// The current element ID (for backward compatibility)
    private var currentElementId: AXElementID?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Updates the current element ID
    /// - Parameter element: The AXUIElement to track
    /// - Returns: The AXElementID for the element
    @discardableResult
    func updateCurrent(_ element: AXUIElement) -> AXElementID {
        let elementId = AXElementID(element)

        // If locked, preserve the existing ID
        if isLocked {
            logger.debug("Registry locked, preserving current element ID")
            return currentElementId ?? elementId
        }

        currentElementId = elementId
        logger.debug("Updated current element ID: \(elementId.debugPointerValue)")

        return elementId
    }

    /// Checks if an element ID matches the current one
    /// - Parameter id: The AXElementID to check
    /// - Returns: true if it matches the current element
    func isValid(_ id: AXElementID) -> Bool {
        currentElementId == id
    }

    /// Locks the registry during user interaction
    func lock() {
        isLocked = true
        logger.info("Registry locked for user interaction")
    }

    /// Unlocks the registry after user interaction
    func unlock() {
        isLocked = false
        logger.info("Registry unlocked")
    }

    /// Returns whether the registry is currently locked
    var locked: Bool {
        isLocked
    }

    /// Clears the current element ID
    func clear() {
        currentElementId = nil
        logger.debug("Cleared current element ID")
    }

    // MARK: - Deprecated Methods (for backward compatibility)

    /// Deprecated: Use TextInjectionService instead
    @available(*, deprecated, message: "Use TextInjectionService to get fresh element references")
    func lookup(_ id: AXElementID) -> AXUIElement? {
        logger.warning("lookup() is deprecated - elements should be acquired fresh at injection time")
        return nil
    }

    /// Deprecated: Use TextInjectionService instead
    @available(*, deprecated, message: "Use TextInjectionService to get fresh element references")
    func getCurrentElement() -> AXUIElement? {
        logger.warning("getCurrentElement() is deprecated - elements should be acquired fresh at injection time")
        return nil
    }
}

// MARK: - AXElementID Extensions

extension AXElementID {
    /// Checks if this ID is the current one in the registry
    @MainActor
    var isCurrent: Bool {
        AXElementRegistry.shared.isValid(self)
    }
}
