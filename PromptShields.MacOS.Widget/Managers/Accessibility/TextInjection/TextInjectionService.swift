import AppKit
import os

// MARK: - Text Injection Protocol

/// Protocol for text injection operations (Interface Segregation Principle)
/// Allows for different injection strategies and easier testing
protocol TextInjectionService: Sendable {
    /// Injects text into the currently focused text field
    /// - Parameters:
    ///   - text: The text to inject
    ///   - targetInfo: Information about the target element (for context)
    /// - Throws: AccessibilityError if injection fails
    @MainActor
    func injectText(_ text: String, targetInfo: ElementInfo?) throws
}

// MARK: - Text Injection Result

/// Result of a text injection attempt
enum TextInjectionResult: Sendable {
    case success
    case elementNotFound
    case elementInvalid
    case injectionFailed(String)
    case applicationNotActive
}

// MARK: - Focused Element Provider Protocol

/// Protocol for acquiring the currently focused element (Single Responsibility)
protocol FocusedElementProvider: Sendable {
    /// Gets the currently focused text element
    /// - Returns: The focused AXUIElement if available
    @MainActor
    func getFocusedElement() -> AXUIElement?

    /// Gets the focused element for a specific application
    /// - Parameter bundleId: The bundle identifier of the target application
    /// - Returns: The focused AXUIElement if available
    @MainActor
    func getFocusedElement(inApplication bundleId: String) -> AXUIElement?
}

// MARK: - Default Focused Element Provider

/// Default implementation that acquires fresh element references
@MainActor
final class DefaultFocusedElementProvider: FocusedElementProvider {
    nonisolated init() {}

    func getFocusedElement() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return getFocusedElement(forApp: frontApp)
    }

    func getFocusedElement(inApplication bundleId: String) -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) else {
            return nil
        }
        return getFocusedElement(forApp: app)
    }

    private func getFocusedElement(forApp app: NSRunningApplication) -> AXUIElement? {
        let bundleId = app.bundleIdentifier ?? ""
        let isBrowser = AXUIElementSafeWrapper.isBrowser(bundleId: bundleId)
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Try to get focused UI element directly
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )

        guard result == .success, let focused = focusedRef else {
            return nil
        }

        let focusedElement = focused as! AXUIElement

        // Verify it's a valid element
        guard AXUIElementSafeWrapper.isValidElement(focusedElement) else {
            return nil
        }

        // For browsers, try to find the actual editable element within web content
        if isBrowser {
            // Check if we're in web content
            if AXUIElementSafeWrapper.isWebContent(focusedElement) {
                // Try to find the actual editable element
                if let editableElement = AXUIElementSafeWrapper.findEditableElementInWebContent(focusedElement) {
                    return editableElement
                }
            }

            // Check if the focused element is editable
            if AXUIElementSafeWrapper.isEditable(focusedElement) ||
               AXUIElementSafeWrapper.isTextInputElement(focusedElement) {
                return focusedElement
            }

            // Search within the focused element for editable content
            if let editableElement = AXUIElementSafeWrapper.findEditableElementInWebContent(focusedElement) {
                return editableElement
            }

            // Try to find web area and search within it
            if let webArea = findWebArea(in: appElement) {
                if let editableElement = AXUIElementSafeWrapper.getFocusedElementInWebContent(webArea) {
                    return editableElement
                }
            }
        }

        return focusedElement
    }

    /// Finds the web area element starting from an app element
    private func findWebArea(in element: AXUIElement) -> AXUIElement? {
        // Try to get the focused window first
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element,
                                         kAXFocusedWindowAttribute as CFString,
                                         &windowRef) == .success,
           let window = AXUIElementSafeWrapper.asAXUIElement(windowRef) {
            return findElementByRole(in: window, role: "AXWebArea", maxDepth: 15)
        }
        return nil
    }

    /// Finds an element by role in the accessibility tree
    private func findElementByRole(in element: AXUIElement, role: String, maxDepth: Int, depth: Int = 0) -> AXUIElement? {
        guard depth < maxDepth, AXUIElementSafeWrapper.isValidElement(element) else { return nil }

        if let elementRole = AXUIElementSafeWrapper.getRole(from: element), elementRole == role {
            return element
        }

        let children = AXUIElementSafeWrapper.getChildren(from: element)
        for child in children {
            if let found = findElementByRole(in: child, role: role, maxDepth: maxDepth, depth: depth + 1) {
                return found
            }
        }

        return nil
    }
}

// MARK: - Default Text Injection Service

/// Production-ready text injection service
/// Re-acquires focused element at injection time for reliability
@MainActor
final class DefaultTextInjectionService: TextInjectionService {
    // MARK: - Properties

    private let focusedElementProvider: FocusedElementProvider
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "TextInjectionService"
    )

    // MARK: - Initialization

    nonisolated init(focusedElementProvider: FocusedElementProvider = DefaultFocusedElementProvider()) {
        self.focusedElementProvider = focusedElementProvider
    }

    // MARK: - TextInjectionService

    func injectText(_ text: String, targetInfo: ElementInfo?) throws {
        logger.debug("Starting text injection, text length: \(text.count)")

        // Step 1: Activate the target application
        let targetBundleId = targetInfo?.applicationBundleId
        let isBrowser = targetBundleId.map { AXUIElementSafeWrapper.isBrowser(bundleId: $0) } ?? false
        try activateTargetApplication(bundleId: targetBundleId)

        // Step 2: Get a fresh reference to the focused element
        let element: AXUIElement
        if let bundleId = targetBundleId {
            guard let focused = focusedElementProvider.getFocusedElement(inApplication: bundleId) else {
                logger.debug("Could not get focused element in target application")
                throw AccessibilityError.failedToGetFocusedElement
            }
            element = focused
        } else {
            guard let focused = focusedElementProvider.getFocusedElement() else {
                logger.debug("Could not get focused element")
                throw AccessibilityError.failedToGetFocusedElement
            }
            element = focused
        }

        // Step 3: Verify element is valid
        guard AXUIElementSafeWrapper.isValidElement(element) else {
            logger.debug("Focused element is not valid")
            throw AccessibilityError.invalidUIElement
        }

        // Step 4: Focus the element
        focusElement(element)

        // Step 5: Determine injection strategy based on context
        let isSelectedText = targetInfo?.isSelectedText ?? false

        if isSelectedText {
            // For browsers, prefer clipboard-based injection as it's more reliable
            if isBrowser {
                try injectAsSelectedTextForBrowser(text, into: element)
            } else {
                try injectAsSelectedText(text, into: element)
            }
        } else {
            if isBrowser {
                try injectAsFullTextForBrowser(text, into: element)
            } else {
                try injectAsFullText(text, into: element)
            }
        }

        logger.debug("Text injection completed successfully")
    }

    // MARK: - Private Methods

    private func activateTargetApplication(bundleId: String?) throws {
        let targetApp: NSRunningApplication?

        if let bundleId = bundleId {
            targetApp = NSWorkspace.shared.runningApplications.first {
                $0.bundleIdentifier == bundleId
            }
        } else {
            targetApp = NSWorkspace.shared.frontmostApplication
        }

        guard let app = targetApp else {
            logger.debug("Target application not found")
            return
        }

        // Activate the application
        app.unhide()
        let activated = app.activate()

        if activated {
            logger.debug("Activated application: \(app.localizedName ?? "unknown")")
        } else {
            logger.debug("Could not activate application, proceeding anyway")
        }

        // Wait for activation
        Thread.sleep(forTimeInterval: 0.15)
    }

    private func focusElement(_ element: AXUIElement) {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        if result == .success {
            logger.debug("Element focused successfully")
        } else {
            logger.debug("Could not set focus (may already be focused)")
        }

        Thread.sleep(forTimeInterval: 0.05)
    }

    private func injectAsFullText(_ text: String, into element: AXUIElement) throws {
        // Strategy 1: Direct value setting
        let directResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )

        if directResult == .success {
            logger.debug("Injected via kAXValueAttribute")
            return
        }

        logger.debug("Direct value failed (\(directResult.rawValue)), trying select-all strategy")

        // Strategy 2: Select all and replace
        if trySelectAllAndReplace(text, in: element) {
            logger.debug("Injected via select-all-replace")
            return
        }

        // Strategy 3: Clipboard paste
        if tryClipboardPaste(text, into: element) {
            logger.debug("Injected via clipboard paste")
            return
        }

        throw AccessibilityError.failedToInjectText
    }

    private func injectAsSelectedText(_ text: String, into element: AXUIElement) throws {
        // Strategy 1: Direct selected text replacement
        let directResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if directResult == .success {
            logger.debug("Replaced selected text via kAXSelectedTextAttribute")
            return
        }

        logger.debug("Direct selected text failed (\(directResult.rawValue)), trying clipboard")

        // Strategy 2: Clipboard paste (replaces selection)
        if tryClipboardPaste(text, into: element) {
            logger.debug("Replaced selected text via clipboard paste")
            return
        }

        throw AccessibilityError.failedToInjectText
    }

    private func trySelectAllAndReplace(_ text: String, in element: AXUIElement) -> Bool {
        // Get current text to determine range
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let currentText = valueRef as? String else {
            return false
        }

        // Select all
        var fullRange = CFRange(location: 0, length: currentText.utf16.count)
        guard let rangeValue = AXValueCreate(.cfRange, &fullRange) else {
            return false
        }

        let selectResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )

        guard selectResult == .success else {
            return false
        }

        // Replace selected text
        let replaceResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        return replaceResult == .success
    }

    private func tryClipboardPaste(_ text: String, into element: AXUIElement) -> Bool {
        // Save clipboard
        let pasteboard = NSPasteboard.general
        let savedContents = pasteboard.string(forType: .string)

        // Set new content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Send Cmd+A then Cmd+V
        let selectAllSent = sendKeyboardShortcut(keyCode: 0x00, command: true) // 'a'
        Thread.sleep(forTimeInterval: 0.05)

        let pasteSent = sendKeyboardShortcut(keyCode: 0x09, command: true) // 'v'
        Thread.sleep(forTimeInterval: 0.1)

        // Restore clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let saved = savedContents {
                pasteboard.setString(saved, forType: .string)
            }
        }

        return selectAllSent && pasteSent
    }

    // MARK: - Browser-Specific Injection Methods

    /// Injects text as selected text replacement for browsers
    /// Browsers often don't support direct accessibility attribute setting, so we use clipboard-first approach
    private func injectAsSelectedTextForBrowser(_ text: String, into element: AXUIElement) throws {
        // Strategy 1: Try clipboard paste (most reliable for browsers)
        if tryClipboardPasteForSelectedText(text, into: element) {
            logger.debug("Browser: Replaced selected text via clipboard paste")
            return
        }

        // Strategy 2: Try direct selected text replacement (may work for some browsers)
        let directResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        if directResult == .success {
            logger.debug("Browser: Replaced selected text via kAXSelectedTextAttribute")
            return
        }

        throw AccessibilityError.failedToInjectText
    }

    /// Injects text as full text replacement for browsers
    private func injectAsFullTextForBrowser(_ text: String, into element: AXUIElement) throws {
        // Strategy 1: Clipboard paste with select all (most reliable)
        if tryClipboardPaste(text, into: element) {
            logger.debug("Browser: Injected via clipboard paste")
            return
        }

        // Strategy 2: Try direct value setting (rarely works for web content)
        let directResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )

        if directResult == .success {
            logger.debug("Browser: Injected via kAXValueAttribute")
            return
        }

        // Strategy 3: Try select-all and replace
        if trySelectAllAndReplace(text, in: element) {
            logger.debug("Browser: Injected via select-all-replace")
            return
        }

        throw AccessibilityError.failedToInjectText
    }

    /// Clipboard paste specifically for replacing selected text (no select-all)
    private func tryClipboardPasteForSelectedText(_ text: String, into element: AXUIElement) -> Bool {
        // Save clipboard
        let pasteboard = NSPasteboard.general
        let savedContents = pasteboard.string(forType: .string)

        // Set new content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Just paste - the selection is already active
        let pasteSent = sendKeyboardShortcut(keyCode: 0x09, command: true) // 'v'
        Thread.sleep(forTimeInterval: 0.1)

        // Restore clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let saved = savedContents {
                pasteboard.setString(saved, forType: .string)
            }
        }

        return pasteSent
    }

    private func sendKeyboardShortcut(keyCode: CGKeyCode, command: Bool) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        if command {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }
}
