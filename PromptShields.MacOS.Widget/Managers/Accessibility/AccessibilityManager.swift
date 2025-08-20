import os
import SwiftUI
import Foundation
import ApplicationServices
import AppKit

actor AccessibilityManagerImpl: ObservableObject {
    private let elementInfo: Binding<ElementInfo?>
    private let applicationInfo: Binding<ApplicationInfo>
    private let isActive: Binding<Bool>
    
    private let pollInterval: TimeInterval = 0.2
    private let timer: PausableTimer
    private let textFieldDetector = TextFieldDetector()
    private var previousText: String?
    private var previousRect: CGRect?
    private var lastIsProcessTrusted: Bool?
    private var shouldDisplayPermissionPrompt = true
    private var shouldDisplayRestartPrompt = true
    private var shouldUpdateFrame = true
    private var shouldUpdateText = true
    
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
        Task {
            UserDefaults.standard.setValue(true, forKey: "shouldHideWelcome")
            isActive.wrappedValue = true
            await timer.start { @MainActor [weak self] in
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
    }
    
    private func analyzeTextIfPossible(element: CFTypeRef) async {
        do {
            try Task.checkCancellation()
            let focusedElement = try await self.getFocusedElementWithRetry()
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

        for attempt in 1...maxRetries {
            do {
                return try await getRobustFocusedElement()
            } catch {
                if attempt == maxRetries {
                    throw error
                }
                try await Task.sleep(nanoseconds: 100_000_000)
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
            
            // Try to get focused element
            if let focusedRef = AXUIElementSafeWrapper.getAttributeValue(from: appElement, attribute: kAXFocusedUIElementAttribute) {
                let focusedElement = focusedRef as! AXUIElement
                // Validate the element is still valid
                guard AXUIElementSafeWrapper.isValidElement(focusedElement) else {
                    return nil
                }
                return focusedElement
            }
            
            // Fallback to window-based search
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
        return AXUIElementSafeWrapper.withMemoryCleanup {
            // Check if this element is focused
            if let focusedValue = AXUIElementSafeWrapper.getAttributeValue(from: element, attribute: kAXFocusedAttribute),
               let boolVal = focusedValue as? Bool, boolVal == true {
                return element
            }
            
            // Get children safely
            let children = AXUIElementSafeWrapper.getChildren(from: element)
            
            for child in children {
                if let found = findFocusedInTree(child) {
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
