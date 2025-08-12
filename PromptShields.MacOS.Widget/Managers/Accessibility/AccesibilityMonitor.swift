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
        if let focusedElement = focusedElement() {
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
                
                if let textField = await self?.textFieldDetector.detectTextField(in: focusedElement, clickPosition: mouseLocation) {
                    await self?.updateOverlayPosition(frame: textField.frame)
                    let text = try await self?.textExtractor.extractText(from: textField)
//                    print("Text \(text)")
//                    logger.error("Extracted text \(text)")
                }
            }
        } catch {
            logger.error("Error received analyzing textfield \(error)")
        }
    }
    
    @MainActor
    func updateOverlayPosition(frame: CGRect) async {
        if frame.origin.x != .infinity && frame.origin.y != .infinity && frame.size.width != 0 && frame.size.height != 0 {
            await self.overlayStateModel.wrappedValue.floatingWindowRect = frame
        }
    }

    @MainActor
    private func getFocusedElementWithRetry() async throws -> AXUIElement {
        let maxRetries = 3

        for attempt in 1...maxRetries {
            do {
                return try await getFocusedElement()
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

    @MainActor
    private func getFocusedElement() async throws -> AXUIElement {
        // First check if we have accessibility permissions
        guard AXIsProcessTrusted() else {
            throw AccessibilityError.noAccessibilityPermissions
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        switch result {
        case .success:
            guard let element = focusedElement else {
                throw AccessibilityError.failedToGetFocusedElement
            }
            return element as! AXUIElement

        case .apiDisabled:
            throw AccessibilityError.accessibilityAPIDisabled

        case .cannotComplete:
            throw AccessibilityError.noAccessibilityPermissions

        case .invalidUIElement:
            throw AccessibilityError.invalidUIElement

        default:
            throw AccessibilityError.unknownError(result)
        }
    }
    
    private func focusedElement() -> CFTypeRef? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        if result == .success {
            return focusedElement
        } else {
            return nil
        }
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
