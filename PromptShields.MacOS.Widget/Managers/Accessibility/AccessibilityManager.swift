import os
import SwiftUI
import Foundation
import ApplicationServices
import AppKit

actor AccessibilityManagerImpl: ObservableObject {
    private let elementInfo: Binding<ElementInfo?>
    private let applicationInfo: Binding<ApplicationInfo>
    private let isActive: Binding<Bool>
    
    private let pollInterval: TimeInterval = 0.5 // Increased from 0.2 to reduce frequency
    private let timer: PausableTimer
    private let textFieldDetector = TextFieldDetector()
    private var previousText: String?
    private var previousRect: CGRect?
    private var lastIsProcessTrusted: Bool?
    private var shouldDisplayPermissionPrompt = true
    private var shouldDisplayRestartPrompt = true
    private var shouldUpdateFrame = true
    private var shouldUpdateText = true
    private var isProcessing = false // Prevent concurrent processing
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AccessibilityManagerImpl.self)
    )
    
    init(elementInfo: Binding<ElementInfo?>,
         applicationInfo: Binding<ApplicationInfo>,
         isActive: Binding<Bool>) {
        self.elementInfo = elementInfo
        self.applicationInfo = applicationInfo
        self.isActive = isActive
        self.timer = PausableTimer(interval: .seconds(pollInterval))
        Task { [weak self] in
            await self?.startTimer()
        }
    }

    func startTimer() {
        UserDefaults.standard.setValue(true, forKey: "shouldHideWelcome")
        isActive.wrappedValue = true
        Task {
            await timer.start { [weak self] in
                await self?.timerTick()
            }
        }
    }
    
    func stopTimer() {
        Task {
            isActive.wrappedValue = false
            await timer.stop()
        }
    }
    
    private func timerTick() {
        if lastIsProcessTrusted == nil && isProcessTrusted {
            logger.log("app has AX")
        } else if lastIsProcessTrusted == nil && !isProcessTrusted {
            logger.log("app does not have AX")
            showPromptIfNeeded()
            // Hide overlay when accessibility is not available
            Task { [weak self] in
                try? Task.checkCancellation()
                await self?.updateElementInfo()
            }
        } else if lastIsProcessTrusted != isProcessTrusted && isProcessTrusted {
            logger.log("user enabled AX")
        } else if lastIsProcessTrusted != isProcessTrusted && !isProcessTrusted {
            logger.log("user disabled AX")
            // Hide overlay when accessibility is disabled
            Task { [weak self] in
                try? Task.checkCancellation()
                await self?.updateElementInfo()
            }
        } else if lastIsProcessTrusted == isProcessTrusted && isProcessTrusted {
//            logger.log("ticking on a trusted process")
            shouldDisplayRestartPrompt = false
            
            // Prevent concurrent processing
            guard !isProcessing else {
                logger.debug("Skipping tick - already processing")
                return
            }
            
            isProcessing = true
            Task { [weak self] in
                try? Task.checkCancellation()
                await self?.onAXAccessGranted()
            }
        } else if lastIsProcessTrusted == isProcessTrusted && !isProcessTrusted {
            logger.log("ticking on a not trusted process")
            // Hide overlay when accessibility is not available
            Task { [weak self] in
                try? Task.checkCancellation()
                await self?.updateElementInfo()
            }
        }
        lastIsProcessTrusted = isProcessTrusted
    }
    
    func showPromptIfNeeded() {
        if shouldDisplayPermissionPrompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [key: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            shouldDisplayPermissionPrompt = false
        }
    }

    deinit {
        // Cancel the timer synchronously to prevent memory leaks
        Task { [weak self] in
            await self?.timer.stop()
        }
    }
    
    private var isProcessTrusted: Bool {
        return AXIsProcessTrusted()
    }
    
    @MainActor
    private func displayRestart() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = """
        Accessibility permissions have been updated, and a restart is required \
        for them to fully take effect. Please quit and reopen the app.
        """
        alert.addButton(withTitle: "OK")

        alert.runModal()
        Task { @MainActor [weak self] in
            try? Task.checkCancellation()
            self?.restartApp()
        }
    }
    
    private func displayRestartIfNeeded() {
        if shouldDisplayRestartPrompt {
            shouldDisplayRestartPrompt = false
            Task { [weak self] in
                try? Task.checkCancellation()
                await self?.displayRestart()
            }
        }
    }

    private func onAXAccessGranted() async {
        if let focusedElement = try? await getRobustFocusedElement() {
            await analyzeTextIfPossible(element: focusedElement)
        } else {
            displayRestartIfNeeded()
            await updateElementInfo()
        }
        isProcessing = false
    }
    
    private func analyzeTextIfPossible(element: CFTypeRef) async {
        do {
            try Task.checkCancellation()
            
            // Use a simple timeout approach without complex concurrency
            let focusedElement = try await getFocusedElementWithRetry()
            
            let isValidElement = await self.isValidElement(focusedElement)
            
            guard isValidElement else {
                self.logger.warning("Focused element is no longer valid")
                await updateElementInfo()
                return
            }
            
            let elementInfo = try self.textFieldDetector.getAXElementOrSelectionInfo(focusedElement)
            await self.updateElementInfo(elementInfo: elementInfo)
//            print("Element info \(elementInfo)")
        } catch {
            logger.error("Error received analyzing textfield \(error)")
            await updateElementInfo()
        }
    }
    
    func updateElementInfo(elementInfo: ElementInfo? = nil) async {
        if let appName = elementInfo?.applicationName {
            applicationInfo.wrappedValue = .init(name: appName)
        } else {
            applicationInfo.wrappedValue = .empty
        }
        let isSelf = elementInfo?.applicationBundleId == Bundle.main.bundleIdentifier
        guard let frame = elementInfo?.frame, frame.isValid else {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                self.elementInfo.wrappedValue = nil
            }
            return
        }
        if !shouldUpdateFrame {
            shouldUpdateFrame = previousRect != elementInfo?.frame
        }
        if !shouldUpdateText {
            shouldUpdateText = previousText != elementInfo?.text
        }
        if shouldUpdateFrame && previousRect == frame {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                self.elementInfo.wrappedValue = elementInfo?.withFrame(frame: frame)
                shouldUpdateFrame = false
            }
        } else if previousRect != elementInfo?.frame {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                self.elementInfo.wrappedValue = nil
            }
        }
        let text = elementInfo?.text
        if shouldUpdateText && previousText == text {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                self.elementInfo.wrappedValue = elementInfo?.withText(text: elementInfo?.text ?? "")
                shouldUpdateText = false
            }
        } else if previousText != elementInfo?.text {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                self.elementInfo.wrappedValue = nil
            }
        }
        
        if elementInfo?.applicationBundleId != nil && !isSelf {
            previousRect = elementInfo?.frame
            previousText = elementInfo?.text
        }
    }

    private func getFocusedElementWithRetry() async throws -> AXUIElement {
        let maxRetries = 3
        let retryDelay: UInt64 = 100_000_000 // 100ms

        let startTime = Date()
        
        for attempt in 1...maxRetries {
            // Check if we've exceeded the total timeout
            if Date().timeIntervalSince(startTime) > 2.0 {
                logger.warning("Total timeout reached while getting focused element")
                throw AccessibilityError.timeout
            }
            
            do {
                return try await getRobustFocusedElement()
            } catch {
                logger.warning("Attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt == maxRetries {
                    throw error
                }
                try await Task.sleep(nanoseconds: retryDelay)
            }
        }

        throw AccessibilityError.failedToGetFocusedElement
    }

    private func isValidElement(_ element: AXUIElement) async -> Bool {
        return AXUIElementSafeWrapper.isValidElement(element)
    }
    
    func getRobustFocusedElement() async throws -> AXUIElement {
        let element: AXUIElement? = AXUIElementSafeWrapper.withMemoryCleanup {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                return nil
            }
            
            guard let appElement = AXUIElementSafeWrapper.createApplicationElement(processIdentifier: frontApp.processIdentifier) else {
                return nil
            }
            
            // Try to get focused element directly first
            if let focusedRef = AXUIElementSafeWrapper.getAttributeValue(from: appElement, attribute: kAXFocusedUIElementAttribute) {
                let focusedElement = focusedRef as! AXUIElement
                // Validate the element is still valid
                guard AXUIElementSafeWrapper.isValidElement(focusedElement) else {
                    return nil
                }
                return focusedElement
            }
            
            // Fallback to window-based search with timeout protection
            if let windowRef = AXUIElementSafeWrapper.getAttributeValue(from: appElement, attribute: kAXFocusedWindowAttribute) {
                let windowElement = windowRef as! AXUIElement
                // Validate the element is still valid
                guard AXUIElementSafeWrapper.isValidElement(windowElement) else {
                    return nil
                }
                
                if let found = findFocusedInTree(windowElement) {
                    return found
                }
            }
            
            return nil
        }
        guard let element else {
            throw AccessibilityError.failedToGetFrame
        }
        return element
    }

    private func findFocusedInTree(_ element: AXUIElement) -> AXUIElement? {
        return findFocusedInTree(element, depth: 0, maxDepth: 20, visitedElements: Set<AXElementID>())
    }
    
    private func findFocusedInTree(_ element: AXUIElement, depth: Int, maxDepth: Int, visitedElements: Set<AXElementID>) -> AXUIElement? {
        // Prevent infinite recursion
        guard depth < maxDepth else {
            logger.warning("Maximum depth reached in findFocusedInTree at depth \(depth)")
            return nil
        }
        
        let elementID = AXElementID(element)
        
        // Prevent cycles by tracking visited elements
        guard !visitedElements.contains(elementID) else {
            logger.warning("Cycle detected in accessibility tree at depth \(depth)")
            return nil
        }
        
        // Log progress for debugging (only at certain depths to avoid spam)
        if depth % 5 == 0 {
            logger.debug("Searching accessibility tree at depth \(depth)")
        }
        
        return AXUIElementSafeWrapper.withMemoryCleanup {
            // Check if this element has text content (indicating it might be focused)
            // Work directly with the original element to avoid reconstruction issues
            let hasValue = AXUIElementSafeWrapper.getAttributeValue(from: element, attribute: kAXValueAttribute) != nil
            let hasSelectedText = AXUIElementSafeWrapper.getAttributeValue(from: element, attribute: kAXSelectedTextRangeAttribute) != nil
            
            if hasValue || hasSelectedText {
                // This element has text content, check if it's the focused element
                guard let frontApp = NSWorkspace.shared.frontmostApplication,
                      let appElement = AXUIElementSafeWrapper.createApplicationElement(processIdentifier: frontApp.processIdentifier),
                      let focusedRef = AXUIElementSafeWrapper.getAttributeValue(from: appElement, attribute: kAXFocusedUIElementAttribute) else {
                    return nil
                }
                
                let focusedElement = focusedRef as! AXUIElement
                
                // Compare the current element with the focused element
                if Unmanaged.passUnretained(element).toOpaque() == Unmanaged.passUnretained(focusedElement).toOpaque() {
                    return element
                }
            }
            
            // Get children safely with a limit to prevent excessive recursion
            let children = AXUIElementSafeWrapper.getChildren(from: element)
            let maxChildren = 50 // Limit to prevent excessive recursion
            
            // Create new set with current element added
            var newVisitedElements = visitedElements
            newVisitedElements.insert(elementID)
            
            for (index, child) in children.enumerated() {
                // Limit the number of children we process
                if index >= maxChildren {
                    logger.warning("Too many children in accessibility tree, stopping search")
                    break
                }
                
                // Skip invalid children
                guard AXUIElementSafeWrapper.isValidElement(child) else {
                    logger.debug("Skipping invalid child element at depth \(depth)")
                    continue
                }
                
                if let found = findFocusedInTree(child, depth: depth + 1, maxDepth: maxDepth, visitedElements: newVisitedElements) {
                    return found
                }
            }
            
            return nil
        }
    }
    
    @MainActor
    func restartApp() {
        guard let bundlePath = Bundle.main.bundlePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return
        }
        let script = """
        sleep 0.5
        open "\(bundlePath)"
        """
        _ = Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", script])

        // Terminate current app
        NSApp.terminate(nil)
    }
}

extension ElementInfo {
    func withFrame(frame: CGRect) -> ElementInfo {
        var copy = self
        copy.frame = frame
        return copy
    }
    
    func withText(text: String) -> ElementInfo {
        var copy = self
        copy.text = text
        return copy
    }
}

extension CGRect {
    var isValid: Bool {
        origin.x != .infinity &&
        origin.y != .infinity &&
        size.width != 0 &&
        size.height != 0
    }
}
