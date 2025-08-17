import AppKit
import os
import Cocoa
import ApplicationServices

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
    
    private func getElementRect(_ element: AXUIElement) throws -> CGRect {
        guard let mainScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else {
            throw AccessibilityError.failedToGetFrame
        }
        let screenHeight = mainScreen.frame.height
        var rectangle: CGRect? = .zero
        
        // Get window clip
        guard let windowClip = getWindowClipRect(for: element, screenHeight: screenHeight) else {
            throw AccessibilityError.failedToGetFrame
        }
        
        var textValue: CFTypeRef?
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
                    let clipped = flippedSel.intersection(windowClip)
                    if !clipped.isEmpty {
                        rectangle = clipped
                    }
                }
            }
        } else if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
           let textString = textValue as? String, !textString.isEmpty {
            // Make range for entire text
            var fullRange = CFRange(location: 0, length: textString.utf16.count)
            if let rangeAXValue = AXValueCreate(.cfRange, &fullRange) {
                var textBoundsValue: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    element,
                    kAXBoundsForRangeParameterizedAttribute as CFString,
                    rangeAXValue,
                    &textBoundsValue
                ) == .success,
                   let textBoundsAXValue = textBoundsValue {
                    var textBounds = CGRect.zero
                    if AXValueGetValue(textBoundsAXValue as! AXValue, .cgRect, &textBounds) {
                        let flippedTextRect = flipRect(textBounds, screenHeight: screenHeight)
                        let clipped = flippedTextRect.intersection(windowClip)
                        if !clipped.isEmpty {
                            rectangle = clipped
                        }
                    }
                }
            }
            
            if let elemFrame = getElementFrameClippedToWindow(element, screenHeight: screenHeight) {
                rectangle = elemFrame
            }
        }
        
        guard let rectangle else {
            throw AccessibilityError.failedToGetFrame
        }
        return CGRect(x: rectangle.origin.x - padding, y: rectangle.origin.y - padding, width: rectangle.size.width + padding * 2, height: rectangle.size.height + padding * 2)
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

    func getAXElementOrSelectionInfo(_ element: AXUIElement) throws -> ElementInfo {
        let applicationInfo = try getApplicationInfo(for: element)
        return .init(text: self.textExtractor.getAllText(from: element),
                     applicationName: applicationInfo.name,
                     applicationBundleId: applicationInfo.bundleId,
                     frame: try getElementRect(element))
    }

    // MARK: - Helpers

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

    private func getElementFrameClippedToWindow(_ element: AXUIElement, screenHeight: CGFloat) -> CGRect? {
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
        
        let elemBottomLeft = CGRect(
            x: originTopLeft.x,
            y: screenHeight - (originTopLeft.y + size.height),
            width: size.width,
            height: size.height
        )
        
        if let windowClip = getWindowClipRect(for: element, screenHeight: screenHeight) {
            return elemBottomLeft.intersection(windowClip)
        } else {
            return elemBottomLeft
        }
    }
}
