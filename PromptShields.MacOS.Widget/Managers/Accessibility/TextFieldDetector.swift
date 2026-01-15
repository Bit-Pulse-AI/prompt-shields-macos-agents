import AppKit
import os
import Cocoa
import ApplicationServices

enum TextFieldDetectorError: Error {
    case nonSelectedError
    case notEditableElement
}
final class TextFieldDetector: Sendable {
    private let textExtractor = TextExtractor()
    private let padding: CGFloat = 4
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: TextFieldDetector.self)
    )

    private func numberOfSelectedCharacters(from value: CFTypeRef?) -> Int {
        var range = CFRange()
        if AXValueGetValue(value as! AXValue, .cfRange, &range) {
            return range.length
        }
        return -1
    }

    func visibleTextRect(for element: AXUIElement) throws -> CGRect {
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
              let rangeValue = selectedRangeValue,
              AXValueGetType(rangeValue as! AXValue) == .cfRange
        else { throw AccessibilityError.failedToGetFrame }

        var cfRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange) else { throw AccessibilityError.failedToGetFrame }

        // Get selected text
        var selectedTextValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
              let selectedText = selectedTextValue as? String
        else { throw AccessibilityError.failedToGetFrame }

        var visibleRects: [CGRect] = []
        var utf16Offset = cfRange.location

        for line in selectedText.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let trimmedLength = trimmedLine.utf16.count

            if trimmedLength > 0 {
                var subrange = CFRange(location: utf16Offset, length: trimmedLength)

                var boundsValue: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXBoundsForRangeParameterizedAttribute as CFString,
                    AXValueCreate(.cfRange, &subrange)!,
                    &boundsValue
                ) == .success,
                   let axRectValue = boundsValue,
                   AXValueGetType(axRectValue as! AXValue) == .cgRect {
                    var rect = CGRect.zero
                    if AXValueGetValue(axRectValue as! AXValue, .cgRect, &rect) {
                        visibleRects.append(rect)
                    }
                }
            }

            // Move offset forward: original line length + 1 for newline
            utf16Offset += line.utf16.count + 1
        }

        return visibleRects.reduce(CGRect.null) { $0.union($1) }
    }

    private func flipRect(_ rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: screenHeight - (rect.origin.y + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    @MainActor
    private func getElementRect(_ element: AXUIElement) throws -> CGRect {
        guard let mainScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else {
            throw AccessibilityError.failedToGetFrame
        }
        let screenHeight = mainScreen.frame.height
        var rectangle: CGRect?

        // Get window clip - may fail for browser web content, so we'll handle that case
        let windowClip = getWindowClipRect(for: element, screenHeight: screenHeight)

        var selRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selRangeValue) == .success,
           let rangeValue = selRangeValue, numberOfSelectedCharacters(from: rangeValue) > 0 {
            var selBoundsValue: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &selBoundsValue
            ) == .success,
               let selBoundsAXValue = selBoundsValue {
                var selBounds = CGRect.zero
                if AXValueGetValue(selBoundsAXValue as! AXValue, .cgRect, &selBounds) {
                    let flippedSel = flipRect(selBounds, screenHeight: screenHeight)
                    // For browsers, window clip might fail - use bounds directly if valid
                    if let windowClip = windowClip {
                        let clipped = flippedSel.intersection(windowClip)
                        if !clipped.isEmpty {
                            rectangle = clipped
                        }
                    }
                    // If no window clip or clipping resulted in empty rect, use the flipped bounds directly
                    if rectangle == nil && flippedSel.width > 0 && flippedSel.height > 0 {
                        rectangle = flippedSel
                    }
                }
            }
        }

        // Fallback: try element's direct frame
        if rectangle == nil {
            if let elemFrame = getElementFrameClippedToWindow(element, screenHeight: screenHeight), !elemFrame.isEmpty {
                rectangle = elemFrame
            } else if let directFrame = getElementDirectFrame(element, screenHeight: screenHeight), !directFrame.isEmpty {
                rectangle = directFrame
            }
        }

        // Last resort fallback for browsers: try to get frame from parent chain
        if rectangle == nil {
            if let parentFrame = getFrameFromParentChain(element, screenHeight: screenHeight) {
                rectangle = parentFrame
            }
        }

        guard let rectangle else {
            throw AccessibilityError.failedToGetFrame
        }
        return CGRect(x: rectangle.origin.x - padding, y: rectangle.origin.y + rectangle.size.height + padding, width: rectangle.size.width + padding * 2, height: rectangle.size.height + padding * 2)
    }

    /// Gets the element's direct frame without window clipping
    private func getElementDirectFrame(_ element: AXUIElement, screenHeight: CGFloat) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              let pos = posValue,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let sz = sizeValue else {
            return nil
        }

        var originTopLeft = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &originTopLeft)
        AXValueGetValue(sz as! AXValue, .cgSize, &size)

        guard size.width > 0 && size.height > 0 else {
            return nil
        }

        return CGRect(
            x: originTopLeft.x,
            y: screenHeight - (originTopLeft.y + size.height),
            width: size.width,
            height: size.height
        )
    }

    /// Traverses parent chain to find a valid frame (useful for browser web content)
    private func getFrameFromParentChain(_ element: AXUIElement, screenHeight: CGFloat) -> CGRect? {
        var currentElement: AXUIElement? = element
        var depth = 0
        let maxDepth = 10

        while let current = currentElement, depth < maxDepth {
            // Try to get frame from this element
            if let frame = getElementDirectFrame(current, screenHeight: screenHeight),
               frame.width > 10 && frame.height > 10 { // Sanity check for reasonable size
                return frame
            }

            // Move to parent
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = AXUIElementSafeWrapper.asAXUIElement(parentRef) else {
                break
            }
            currentElement = parent
            depth += 1
        }

        return nil
    }

    private func getApplicationInfo(for element: AXUIElement) throws -> (name: String, bundleId: String) {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)

        guard result == .success else {
            throw AccessibilityError.failedToGetApplicationInfo
        }

        let app = NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }

        return (
            name: app?.localizedName ?? "Unknown",
            bundleId: app?.bundleIdentifier ?? "unknown"
        )
    }

    @MainActor
    func getAXElementOrSelectionInfo(_ element: AXUIElement) throws -> ElementInfo {
        let applicationInfo = try getApplicationInfo(for: element)
        let isBrowser = AXUIElementSafeWrapper.isBrowser(bundleId: applicationInfo.bundleId)

        // First check if there's selected text
        let selectedText = AXUIElementSafeWrapper.getSelectedText(from: element)
        let isFromSelection = selectedText != nil && !selectedText!.isEmpty

        // For non-browsers, require selected text
        // For browsers, also detect editable fields without selection
        if !isFromSelection {
            // Check if this is an editable element (especially important for browsers)
            let isEditable = AXUIElementSafeWrapper.isEditable(element) ||
                            AXUIElementSafeWrapper.isTextInputElement(element)

            if !isEditable {
                throw TextFieldDetectorError.nonSelectedError
            }

            // For editable fields without selection, still require selected text for action
            // This maintains the current behavior but allows the element to be tracked
            if !isBrowser {
                throw TextFieldDetectorError.nonSelectedError
            }
        }

        let text: String
        if let selectedText = selectedText, !selectedText.isEmpty {
            // Use selected text directly
            text = selectedText
        } else {
            // For editable fields without selection, we need to handle this case
            // For now, require selection for the action to appear
            throw TextFieldDetectorError.nonSelectedError
        }

        // Register the element in the registry and get its ID
        // This allows us to look up the actual AXUIElement later when needed
        let elementId = AXElementRegistry.shared.updateCurrent(element)

        return ElementInfo(
            text: text,
            applicationName: applicationInfo.name,
            applicationBundleId: applicationInfo.bundleId,
            frame: try getElementRect(element),
            elementIdentifier: elementId,
            isSelectedText: isFromSelection
        )
    }

    // MARK: - Helpers

    @MainActor
    private func getWindowClipRect(for element: AXUIElement, screenHeight: CGFloat) -> CGRect? {
        // Try direct window attribute first
        var windowRef: CFTypeRef?
        var windowElement: AXUIElement?

        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
           let window = AXUIElementSafeWrapper.asAXUIElement(windowRef) {
            windowElement = window
        } else {
            // For browsers, traverse parent chain to find window
            windowElement = findWindowInParentChain(element)
        }

        guard let window = windowElement else {
            return nil
        }

        var winPosValue: CFTypeRef?
        var winSizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &winPosValue) == .success,
              let winPos = winPosValue,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &winSizeValue) == .success,
              let winSize = winSizeValue else {
            return nil
        }

        var winOriginTopLeft = CGPoint.zero
        var winSizeCGSize = CGSize.zero
        AXValueGetValue(winPos as! AXValue, .cgPoint, &winOriginTopLeft)
        AXValueGetValue(winSize as! AXValue, .cgSize, &winSizeCGSize)

        return CGRect(
            x: winOriginTopLeft.x,
            y: screenHeight - (winOriginTopLeft.y + winSizeCGSize.height),
            width: winSizeCGSize.width,
            height: winSizeCGSize.height
        )
    }

    /// Finds a window element by traversing the parent chain
    @MainActor
    private func findWindowInParentChain(_ element: AXUIElement) -> AXUIElement? {
        var currentElement: AXUIElement? = element
        var depth = 0
        let maxDepth = 20

        while let current = currentElement, depth < maxDepth {
            // Check if this element is a window
            if let role = AXUIElementSafeWrapper.getRole(from: current), role == "AXWindow" {
                return current
            }

            // Try the window attribute of this element
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXWindowAttribute as CFString, &windowRef) == .success,
               let window = AXUIElementSafeWrapper.asAXUIElement(windowRef) {
                return window
            }

            // Move to parent
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                  let parent = AXUIElementSafeWrapper.asAXUIElement(parentRef) else {
                break
            }
            currentElement = parent
            depth += 1
        }

        return nil
    }

    @MainActor
    private func getElementFrameClippedToWindow(_ element: AXUIElement, screenHeight: CGFloat) -> CGRect? {
        guard let directFrame = getElementDirectFrame(element, screenHeight: screenHeight) else {
            return nil
        }

        if let windowClip = getWindowClipRect(for: element, screenHeight: screenHeight) {
            let clipped = directFrame.intersection(windowClip)
            return clipped.isEmpty ? directFrame : clipped
        } else {
            return directFrame
        }
    }
}
