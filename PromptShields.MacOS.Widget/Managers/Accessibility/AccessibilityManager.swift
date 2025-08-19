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
        Task {
            await startTimer()
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
                await self?.updateElementInfo()
            }
        } else if lastIsProcessTrusted != isProcessTrusted && isProcessTrusted {
            logger.log("user enabled AX")
        } else if lastIsProcessTrusted != isProcessTrusted && !isProcessTrusted {
            logger.log("user disabled AX")
            // Hide overlay when accessibility is disabled
            Task { [weak self] in
                await self?.updateElementInfo()
            }
        } else if lastIsProcessTrusted == isProcessTrusted && isProcessTrusted {
//            logger.log("ticking on a trusted process")
            shouldDisplayRestartPrompt = false
            Task { [weak self] in
                await self?.onAXAccessGranted()
            }
        } else if lastIsProcessTrusted == isProcessTrusted && !isProcessTrusted {
            logger.log("ticking on a not trusted process")
            // Hide overlay when accessibility is not available
            Task { [weak self] in
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
        Task { [weak self] in
            await self?.stopTimer()
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
            self?.restartApp()
        }
    }
    
    private func displayRestartIfNeeded() {
        if shouldDisplayRestartPrompt {
            shouldDisplayRestartPrompt = false
            Task { [weak self] in
                await self?.displayRestart()
            }
        }
    }

    private func onAXAccessGranted() async {
        if let focusedElement = try? getRobustFocusedElement() {
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
        
        if shouldUpdateFrame && previousRect == elementInfo?.frame {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                self.elementInfo.wrappedValue = elementInfo?.withFrame(frame: frame)
                shouldUpdateFrame = false
            }
        } else if previousRect != elementInfo?.frame {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                self.elementInfo.wrappedValue = nil
            }
        }
        
        if shouldUpdateText && previousText == elementInfo?.text {
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
                return try getRobustFocusedElement()
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
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        guard result == .success else {
            return false
        }
        let app = NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
        return app != nil
    }
    
    func getRobustFocusedElement() throws -> AXUIElement {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw AccessibilityError.failedToGetFrame
        }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focusedElement = focusedRef {
            return focusedElement as! AXUIElement
        }
        
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) != .success {
            throw AccessibilityError.failedToGetFrame
        }
        guard let windowElement = windowRef else {
            throw AccessibilityError.failedToGetFrame
        }
        
        if let found = findFocusedInTree(windowElement as! AXUIElement) {
            return found
        }
        
        throw AccessibilityError.failedToGetFrame
    }

    private func findFocusedInTree(_ element: AXUIElement) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focusedValue) == .success,
           let boolVal = focusedValue as? Bool, boolVal == true {
            return element
        }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) != .success {
            return nil
        }
        guard let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        
        for child in children {
            if let found = findFocusedInTree(child) {
                return found
            }
        }
        
        return nil
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
