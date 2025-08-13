import AppKit
import os
import Cocoa
import ApplicationServices

actor TextFieldDetector {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: TextFieldDetector.self)
    )

    func getAXElementClippedFrameOrSelection(_ element: AXUIElement) -> CGRect? {
        print("element \(element)")
        guard let mainScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) else {
            return nil
        }
        let screenHeight = mainScreen.frame.height
        
        func flipRect(_ rect: CGRect) -> CGRect {
            CGRect(
                x: rect.origin.x,
                y: screenHeight - (rect.origin.y + rect.height),
                width: rect.width,
                height: rect.height
            )
        }
        
        // Get window clip
        guard let windowClip = getWindowClipRect(for: element, screenHeight: screenHeight) else {
            return nil
        }
        
        // 1 — Try selection first
        var selRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selRangeValue) == .success,
           let rangeValue = selRangeValue {
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
                    let flippedSel = flipRect(selBounds)
                    let clipped = flippedSel.intersection(windowClip)
                    if !clipped.isEmpty {
                        return clipped
                    }
                }
            }
        }
        
        // 2 — No selection: try to trim whitespace by using text bounds
        var textValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
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
                        let flippedTextRect = flipRect(textBounds)
                        let clipped = flippedTextRect.intersection(windowClip)
                        if !clipped.isEmpty {
                            return clipped
                        }
                    }
                }
            }
        }
        
        // 3 — Fallback: clipped element frame
        if let elemFrame = getElementFrameClippedToWindow(element, screenHeight: screenHeight) {
            return elemFrame
        }
        
        return nil
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
