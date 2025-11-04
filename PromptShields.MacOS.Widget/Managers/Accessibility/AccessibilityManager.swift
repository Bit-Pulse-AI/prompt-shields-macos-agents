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
        Task { [weak self] in
            await self?.setIsActiveOnMain(true)
        }
        Task {
            await timer.start { [weak self] in
                await self?.timerTick()
            }
        }
    }

    func stopTimer() {
        Task { [weak self] in
            await self?.setIsActiveOnMain(false)
            await self?.timer.stop()
            await self?.setElementInfoOnMain(nil)
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
            await setApplicationInfoOnMain(.init(name: appName))
        } else {
            await setApplicationInfoOnMain(.empty)
        }
        let isSelf = elementInfo?.applicationBundleId == Bundle.main.bundleIdentifier
        guard let frame = elementInfo?.frame, frame.isValid else {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                await setElementInfoOnMain(nil)
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
                await setElementInfoOnMain(elementInfo?.withFrame(frame: frame))
                shouldUpdateFrame = false
            }
        } else if previousRect != elementInfo?.frame {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                await setElementInfoOnMain(nil)
            }
        }
        let text = elementInfo?.text
        if shouldUpdateText && previousText == text {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                await setElementInfoOnMain(elementInfo?.withText(text: elementInfo?.text ?? ""))
                shouldUpdateText = false
            }
        } else if previousText != elementInfo?.text {
            if elementInfo?.applicationBundleId != nil && !isSelf {
                await setElementInfoOnMain(nil)
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
        let element: AXUIElement? = await MainActor.run {
            func localFindFocusedInTree(_ element: AXUIElement, depth: Int, maxDepth: Int, visited: Set<AXElementID>) -> AXUIElement? {
                guard depth < maxDepth else { return nil }
                let elementID = AXElementID(element)
                guard !visited.contains(elementID) else { return nil }
                if AXUIElementSafeWrapper.getAttributeValue(from: element, attribute: kAXValueAttribute) != nil ||
                    AXUIElementSafeWrapper.getAttributeValue(from: element, attribute: kAXSelectedTextRangeAttribute) != nil {
                    if let frontApp = NSWorkspace.shared.frontmostApplication,
                       let appElement = AXUIElementSafeWrapper.createApplicationElement(processIdentifier: frontApp.processIdentifier),
                       let focusedRef = AXUIElementSafeWrapper.getAttributeValue(from: appElement, attribute: kAXFocusedUIElementAttribute) {
                        let focusedElement = focusedRef as! AXUIElement
                        if Unmanaged.passUnretained(element).toOpaque() == Unmanaged.passUnretained(focusedElement).toOpaque() {
                            return element
                        }
                    }
                }
                let children = AXUIElementSafeWrapper.getChildren(from: element)
                var newVisited = visited
                newVisited.insert(elementID)
                for child in children {
                    if let found = localFindFocusedInTree(child, depth: depth + 1, maxDepth: maxDepth, visited: newVisited) {
                        return found
                    }
                }
                return nil
            }

            return AXUIElementSafeWrapper.withMemoryCleanup {
                guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                    return nil
                }
                guard let appElement = AXUIElementSafeWrapper.createApplicationElement(processIdentifier: frontApp.processIdentifier) else {
                    return nil
                }
                if let focusedRef = AXUIElementSafeWrapper.getAttributeValue(from: appElement, attribute: kAXFocusedUIElementAttribute) {
                    let focusedElement = focusedRef as! AXUIElement
                    guard AXUIElementSafeWrapper.isValidElement(focusedElement) else { return nil }
                    return focusedElement
                }
                if let windowRef = AXUIElementSafeWrapper.getAttributeValue(from: appElement, attribute: kAXFocusedWindowAttribute) {
                    let windowElement = windowRef as! AXUIElement
                    guard AXUIElementSafeWrapper.isValidElement(windowElement) else { return nil }
                    return localFindFocusedInTree(windowElement, depth: 0, maxDepth: 20, visited: Set<AXElementID>())
                }
                return nil
            }
        }
        guard let element else {
            throw AccessibilityError.failedToGetFrame
        }
        return element
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

    @MainActor
    private func setIsActiveOnMain(_ value: Bool) {
        isActive.wrappedValue = value
    }

    @MainActor
    private func setApplicationInfoOnMain(_ value: ApplicationInfo) {
        applicationInfo.wrappedValue = value
    }

    @MainActor
    private func setElementInfoOnMain(_ value: ElementInfo?) {
        elementInfo.wrappedValue = value
    }
}

extension ElementInfo {
    func withFrame(frame: CGRect) -> ElementInfo {
        return ElementInfo(text: self.text,
                          applicationName: self.applicationName,
                          applicationBundleId: self.applicationBundleId,
                          frame: frame,
                          element: self.element,
                          isSelectedText: self.isSelectedText)
    }

    func withText(text: String) -> ElementInfo {
        return ElementInfo(text: text,
                          applicationName: self.applicationName,
                          applicationBundleId: self.applicationBundleId,
                          frame: self.frame,
                          element: self.element,
                          isSelectedText: self.isSelectedText)
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
