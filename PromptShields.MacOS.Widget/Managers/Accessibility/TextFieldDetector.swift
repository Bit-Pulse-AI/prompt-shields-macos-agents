import AppKit
import os

actor TextFieldDetector {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: TextFieldDetector.self)
    )
    
    private let supportedRoles = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXStaticTextRole as String,
        "AXText" // Some applications use custom roles
    ]
    
    private let supportedTypes = [
        "NSTextField",
        "NSTextView",
        "NSScrollView",
        "NSView"
    ]
    
    // Applications that might need special handling
    private let specialHandlingApps = [
        "com.tinyspeck.slackmacgap", // Slack
        "com.cursor.Cursor", // Cursor
        "com.microsoft.VSCode", // VS Code
        "com.jetbrains.intellij" // IntelliJ
    ]
    @MainActor
    func getAXElementClippedFrameOrSelection(_ element: AXUIElement, clickPosition: CGPoint? = nil) async throws -> CGRect {
        // Helper to flip coordinates
        func flipRect(_ rect: CGRect, screenHeight: CGFloat) -> CGRect {
            CGRect(
                x: rect.origin.x,
                y: screenHeight - (rect.origin.y + rect.height),
                width: rect.width,
                height: rect.height
            )
        }
        
        guard let mainScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else {
            throw AccessibilityError.failedToGetFrame
        }
        let screenHeight = mainScreen.frame.height
        
        // Get application info for debugging and special handling
        let appInfo = try? await getApplicationInfo(for: element)
        let isSpecialApp = specialHandlingApps.contains(where: { app in
            app == appInfo?.bundleId
        })
        
        if isSpecialApp {
            logger.debug("Processing special app: \(appInfo?.name ?? "Unknown") (\(appInfo?.bundleId ?? "unknown"))")
            
            // Try special handling first for problematic applications
            if let appInfo = appInfo,
               let specialFrame = handleSpecialApplication(element, appInfo: appInfo, screenHeight: screenHeight) {
//                logger.debug("Special handling returned frame: \(specialFrame)")
                return specialFrame
            }
        }
        
        // If we have a click position, try to find the most specific child element
        if let clickPos = clickPosition {
            if let childElement = findChildElementAtPosition(element, position: clickPos, screenHeight: screenHeight) {
//                logger.debug("Found child element at click position: \(clickPos)")
                // Recursively call this method on the child element
                return try await getAXElementClippedFrameOrSelection(childElement, clickPosition: clickPos)
            }
        }
        
        // Try to get selected text range
        var selRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selRangeValue) == .success,
           let rangeValue = selRangeValue {
            // Check if the range has length (not empty selection)
            var range = NSRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                logger.debug("Text range found: location=\(range.location), length=\(range.length)")
                
                // If range length is 0, return window rectangle
                if range.length == 0 {
                    logger.debug("Empty text range, returning window rectangle")
                    if let windowClip = getWindowClipRect(for: element, screenHeight: screenHeight) {
                        return windowClip
                    }
                } else {
                    // Get bounds for that range
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
//                            logger.debug("Selection bounds: \(selBounds)")
                            // Clip to window
                            if let windowClip = getWindowClipRect(for: element, screenHeight: screenHeight) {
                                let flippedSel = flipRect(selBounds, screenHeight: screenHeight)
                                let clipped = flippedSel.intersection(windowClip)
                                if !clipped.isEmpty {
//                                    logger.debug("Returning clipped selection bounds: \(clipped)")
                                    return clipped
                                } else {
                                    logger.warning("Clipped selection bounds is empty")
                                }
                            }
                        } else {
                            logger.warning("Failed to get selection bounds value")
                        }
                    } else {
                        logger.warning("Failed to get bounds for range")
                    }
                }
            } else {
                logger.warning("Failed to get range value")
            }
        } else {
            logger.debug("No selected text range found")
        }
        
        // Fallback: clipped element frame
        if let elemFrame = getElementFrameClippedToWindow(element, screenHeight: screenHeight) {
//            logger.debug("Returning element frame: \(elemFrame)")
            return elemFrame
        }
        
        logger.error("Failed to get any frame for element")
        throw AccessibilityError.failedToGetFrame
    }

    // MARK: - Child Element Detection

    @MainActor
    private func findChildElementAtPosition(_ parentElement: AXUIElement, position: CGPoint, screenHeight: CGFloat) -> AXUIElement? {
        // Get children of the parent element
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parentElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return nil
        }
        
        // Find the child element that contains the click position
        for child in children {
            if let childFrame = getElementFrameClippedToWindow(child, screenHeight: screenHeight),
               childFrame.contains(position) {
                // Check if this child has its own children (recursive search)
                if let grandChild = findChildElementAtPosition(child, position: position, screenHeight: screenHeight) {
                    return grandChild
                }
                return child
            }
        }
        
        return nil
    }

    // MARK: - Helpers

    @MainActor
    private func getWindowClipRect(for element: AXUIElement, screenHeight: CGFloat) -> CGRect? {
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
              let windowElement = windowRef else {
            return nil
        }
        
        var winPosValue: CFTypeRef?
        var winSizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXPositionAttribute as CFString, &winPosValue) == .success,
              let winPos = winPosValue,
              AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXSizeAttribute as CFString, &winSizeValue) == .success,
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

    @MainActor
    private func getElementFrameClippedToWindow(_ element: AXUIElement, screenHeight: CGFloat) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              let pos = posValue,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let sz = sizeValue else {
            logger.warning("Failed to get position or size attributes")
            return nil
        }
        
        var originTopLeft = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &originTopLeft),
              AXValueGetValue(sz as! AXValue, .cgSize, &size) else {
            logger.warning("Failed to extract position or size values")
            return nil
        }
        
//        logger.debug("Element position: \(originTopLeft), size: \(size)")
        
        let elemBottomLeft = CGRect(
            x: originTopLeft.x,
            y: screenHeight - (originTopLeft.y + size.height),
            width: size.width,
            height: size.height
        )
        
//        logger.debug("Element frame (flipped): \(elemBottomLeft)")
        
        if let windowClip = getWindowClipRect(for: element, screenHeight: screenHeight) {
            let clipped = elemBottomLeft.intersection(windowClip)
//            logger.debug("Window clip: \(windowClip), clipped result: \(clipped)")
            return clipped
        } else {
//            logger.warning("No window clip available, returning element frame")
            return elemBottomLeft
        }
    }
    
    // MARK: - Special Application Handling
    
    @MainActor
    private func handleSpecialApplication(_ element: AXUIElement, appInfo: (name: String, bundleId: String), screenHeight: CGFloat) -> CGRect? {
        logger.debug("Applying special handling for: \(appInfo.name)")
        
        switch appInfo.bundleId {
        case "com.tinyspeck.slackmacgap":
            return handleSlackElement(element, screenHeight: screenHeight)
        case "com.cursor.Cursor":
            return handleCursorElement(element, screenHeight: screenHeight)
        default:
            return nil
        }
    }
    
    @MainActor
    private func handleSlackElement(_ element: AXUIElement, screenHeight: CGFloat) -> CGRect? {
        // Slack often has nested text elements that need special handling
        logger.debug("Handling Slack element")
        
        // Try to find a more specific text element within the focused element
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                var roleValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
                   let role = roleValue as? String {
                    if role == kAXStaticTextRole as String || role == kAXTextFieldRole as String {
                        logger.debug("Found Slack text element with role: \(role)")
                        return getElementFrameClippedToWindow(child, screenHeight: screenHeight)
                    }
                }
            }
        }
        
        return nil
    }
    
    @MainActor
    private func handleCursorElement(_ element: AXUIElement, screenHeight: CGFloat) -> CGRect? {
        // Cursor (VS Code-based) often has complex nested structures
        logger.debug("Handling Cursor element")
        
        // Try to find the actual text editor element
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                var roleValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
                   let role = roleValue as? String {
                    if role == kAXTextAreaRole as String || role == kAXTextFieldRole as String {
                        logger.debug("Found Cursor text element with role: \(role)")
                        return getElementFrameClippedToWindow(child, screenHeight: screenHeight)
                    }
                }
            }
        }
        
        return nil
    }
    
    @MainActor
    func detectTextField(in element: AXUIElement, clickPosition: CGPoint? = nil) async -> TextFieldInfo? {
        do {
            // Get application information first for debugging
            let appInfo = try await getApplicationInfo(for: element)
            logger.debug("Detecting text field in: \(appInfo.name) (\(appInfo.bundleId))")
            
            if let clickPos = clickPosition {
//                logger.debug("Click position provided: \(clickPos)")
            }
            
            // Get element properties
//            let role = try await getAttribute(element, kAXRoleAttribute as CFString) as? String
//            let type = try await getAttribute(element, kAXSubroleAttribute as CFString) as? String
            let frame = try await getAXElementClippedFrameOrSelection(element, clickPosition: clickPosition)
//            logger.debug("Final frame detected: \(frame)")
            
            return TextFieldInfo(
                element: element,
                applicationName: appInfo.name,
                applicationBundleId: appInfo.bundleId,
                elementType: "Unknown",
                elementRole: "role",
                frame: frame
            )
        } catch {
            logger.error("Error detecting text field: \(error)")
            return nil
        }
    }
    @MainActor
    private func getAttribute(_ element: AXUIElement, _ attribute: CFString) async throws -> CFTypeRef {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        
        guard result == .success, let value = value else {
            throw AccessibilityError.failedToGetAttribute(attribute as String)
        }
        
        return value
    }
    
    @MainActor
    private func getApplicationInfo(for element: AXUIElement) async throws -> (name: String, bundleId: String) {
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
}
