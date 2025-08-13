import os
import SwiftUI
import Foundation
import ApplicationServices
import AppKit

actor AccessibilityMonitorService: ObservableObject {
    private var overlayStateModel: StateObject<OverlayStateModel>
    
    private let pollInterval: TimeInterval = 0.5
    private var timer: DispatchSourceTimer?
    private var lastIsProcessTrusted: Bool?
    private var shouldDisplayPermissionPrompt = true
    private var shouldDisplayRestartPrompt = true
    
    private let textFieldDetector = TextFieldDetector()
    private let textExtractor = TextExtractor()
    private let textInjector = TextInjector()
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AccessibilityMonitorService.self)
    )
    
    init(overlayStateModel: StateObject<OverlayStateModel>) {
        self.overlayStateModel = overlayStateModel
        Task { [weak self] in
            await self?.startTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }

        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        source.schedule(deadline: .now(), repeating: pollInterval, leeway: .milliseconds(200))
        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.timerTick()
            }
        }

        self.timer = source
        source.resume()
    }
    
    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
    
    private func timerTick() {
//        var reset = false
        if lastIsProcessTrusted == nil && isProcessTrusted {
            logger.log("app has AX")
        } else if lastIsProcessTrusted == nil && !isProcessTrusted {
            logger.log("app does not have AX")
            showPromptIfNeeded()
        } else if lastIsProcessTrusted != isProcessTrusted && isProcessTrusted {
            logger.log("user enabled AX")
        } else if lastIsProcessTrusted != isProcessTrusted && !isProcessTrusted {
            logger.log("user disabled AX")
//            reset = true
        } else if lastIsProcessTrusted == isProcessTrusted && isProcessTrusted {
            logger.log("ticking on a trusted process")
            shouldDisplayRestartPrompt = false
            onAXAccessGranted()
        } else if lastIsProcessTrusted == isProcessTrusted && !isProcessTrusted {
            logger.log("ticking on a not trusted process")
        }
        lastIsProcessTrusted = isProcessTrusted
//        if reset {
//            shouldDisplayRestartPrompt = true
//            lastIsProcessTrusted = nil
//            shouldDisplayPermissionPrompt = true
//            reset = false
//        }
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
        // Example: show a polite alert to the user
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

    private func onAXAccessGranted() {
        if let focusedElement = try? getRobustFocusedElement() {
            analyzeTextIfPossible(element: focusedElement)
        } else {
            displayRestartIfNeeded()
        }
    }
    
    private func analyzeTextIfPossible(element: CFTypeRef) {
        Task { [weak self] in
            await self?.monitorActiveTextField()
        }
    }

    @MainActor
    private func monitorActiveTextField() async {
        do {
            // Check if task is cancelled
            try Task.checkCancellation()
            let focusedElement = try await self.getFocusedElementWithRetry()
            
            let isValidElement = await self.isValidElement(focusedElement)
            // Validate the element is still accessible
            guard isValidElement else {
                self.logger.warning("Focused element is no longer valid")
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                return
            }
            
            Task { @MainActor @Sendable [weak self] in
                // Get current mouse position for click-based child detection
                let mouseLocation = NSEvent.mouseLocation
                
                if let textField = await self?.textFieldDetector.getAXElementClippedFrameOrSelection(focusedElement) {
                    await self?.updateOverlayPosition(frame: textField)
//                    let text = try await self?.textExtractor.extractText(from: textField)
//                    print("Text \(text)")
//                    logger.error("Extracted text \(text)")
                }
            }
        } catch {
            logger.error("Error received analyzing textfield \(error)")
        }
    }
    
    private let padding: CGFloat = 8
    @MainActor
    func updateOverlayPosition(frame: CGRect) async {
        if frame.origin.x != .infinity && frame.origin.y != .infinity && frame.size.width != 0 && frame.size.height != 0 {
            await self.overlayStateModel.wrappedValue.floatingWindowRect = CGRect(x: frame.origin.x - padding, y: frame.origin.y - padding, width: frame.size.width + padding * 2, height: frame.size.height + padding * 2)
        }
    }

    @MainActor
    private func getFocusedElementWithRetry() async throws -> AXUIElement {
        let maxRetries = 3

        for attempt in 1...maxRetries {
            do {
                return try await getRobustFocusedElement()
            } catch {
                if attempt == maxRetries {
                    throw error
                }

                // Wait before retry
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }

        throw AccessibilityError.failedToGetFocusedElement
    }

    @MainActor
    private func isValidElement(_ element: AXUIElement) async -> Bool {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)

        guard result == .success else {
            return false
        }

        // Check if the process is still running
        let app = NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
        return app != nil
    }
    
    func getRobustFocusedElement() throws -> AXUIElement {
        // Step 1 — Try direct kAXFocusedUIElementAttribute
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw AccessibilityError.failedToGetFrame
        }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let focusedElement = focusedRef {
            return focusedElement as! AXUIElement
        }
        
        // Step 2 — Get focused window
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) != .success {
            throw AccessibilityError.failedToGetFrame
        }
        guard let windowElement = windowRef else {
            throw AccessibilityError.failedToGetFrame
        }
        
        // Step 3 — Search recursively for AXFocused = true
        if let found = findFocusedInTree(windowElement as! AXUIElement) {
            return found
        }
        
        throw AccessibilityError.failedToGetFrame
    }

    // Recursively search children for AXFocused = true
    private func findFocusedInTree(_ element: AXUIElement) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focusedValue) == .success,
           let boolVal = focusedValue as? Bool, boolVal == true {
            return element
        }
        
        // Get children
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

        // Use `open` to launch the same bundle after a short delay
        let script = """
        sleep 0.5
        open "\(bundlePath)"
        """

        // Spawn a shell process to run the restart command
        _ = Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", script])

        // Terminate current app
        NSApp.terminate(nil)
    }
}
