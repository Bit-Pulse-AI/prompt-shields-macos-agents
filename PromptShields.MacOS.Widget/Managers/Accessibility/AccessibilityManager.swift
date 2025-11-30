import os
import SwiftUI
import Foundation
import ApplicationServices
import AppKit

// MARK: - Accessibility Manager

/// Manages accessibility operations for detecting and interacting with focused text fields.
/// Uses MainActor isolation for all AXUIElement operations to ensure Swift 6 compliance.
@MainActor
final class AccessibilityManagerImpl: ObservableObject {
    // MARK: - Published Properties

    @Published var elementInfo: ElementInfo?
    @Published var applicationInfo: ApplicationInfo = .empty
    @Published var isActive: Bool = false

    // MARK: - Private Properties

    private let pollInterval: TimeInterval = 0.5
    private var timerTask: Task<Void, Never>?
    private let textFieldDetector = TextFieldDetector()
    private var previousText: String?
    private var previousRect: CGRect?
    private var lastIsProcessTrusted: Bool?
    private var shouldDisplayPermissionPrompt = true
    private var shouldDisplayRestartPrompt = true
    private var shouldUpdateFrame = true
    private var shouldUpdateText = true
    private var isProcessing = false
    private var savedIsActiveState: Bool?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AccessibilityManagerImpl.self)
    )

    // MARK: - Initialization

    init() {
        setupSystemLockObservers()
        startTimer()
    }

    deinit {
        timerTask?.cancel()
    }

    // MARK: - Timer Control

    func startTimer() {
        UserDefaults.standard.setValue(true, forKey: "shouldHideWelcome")
        isActive = true

        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.timerTick()
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 0.5))
            }
        }
    }

    func stopTimer() {
        isActive = false
        timerTask?.cancel()
        timerTask = nil
        elementInfo = nil
    }

    // MARK: - System Lock Observers

    private func setupSystemLockObservers() {
        let dnc = DistributedNotificationCenter.default()

        dnc.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) {_ in
            Task { @MainActor [weak self] in
                self?.savedIsActiveState = self?.isActive
                self?.isActive = false
            }
        }

        dnc.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                if let savedState = self?.savedIsActiveState {
                    self?.isActive = savedState
                    self?.savedIsActiveState = nil
                }
            }
        }
    }

    // MARK: - Timer Tick

    private func timerTick() async {
        let trusted = isProcessTrusted

        if lastIsProcessTrusted == nil && trusted {
            logger.log("App has accessibility permissions")
        } else if lastIsProcessTrusted == nil && !trusted {
            logger.log("App does not have accessibility permissions")
            showPromptIfNeeded()
            clearElementInfo()
        } else if lastIsProcessTrusted != trusted && trusted {
            logger.log("User enabled accessibility permissions")
        } else if lastIsProcessTrusted != trusted && !trusted {
            logger.log("User disabled accessibility permissions")
            clearElementInfo()
        } else if lastIsProcessTrusted == trusted && trusted {
            // Prevent concurrent processing
            guard !isProcessing else {
                logger.debug("Skipping tick - already processing")
                return
            }

            isProcessing = true
            await processAccessibility()
            isProcessing = false
        } else if lastIsProcessTrusted == trusted && !trusted {
            logger.log("Ticking on untrusted process")
            clearElementInfo()
        }

        lastIsProcessTrusted = trusted
    }

    // MARK: - Accessibility Processing

    private func processAccessibility() async {
        do {
            guard let focusedElement = try getFocusedElementWithRetry() else {
                displayRestartIfNeeded()
                clearElementInfo()
                return
            }

            guard AXUIElementSafeWrapper.isValidElement(focusedElement) else {
                logger.warning("Focused element is no longer valid")
                clearElementInfo()
                return
            }

            let info = try textFieldDetector.getAXElementOrSelectionInfo(focusedElement)
            updateElementInfo(info)
        } catch {
            logger.error("Error analyzing text field: \(error.localizedDescription)")
            clearElementInfo()
        }
    }

    /// Gets the focused element with retry logic
    /// All operations stay on MainActor - no Sendable boundary crossing
    private func getFocusedElementWithRetry() throws -> AXUIElement? {
        let maxRetries = 3
        let startTime = Date()

        for attempt in 1...maxRetries {
            // Check timeout
            if Date().timeIntervalSince(startTime) > 2.0 {
                logger.warning("Total timeout reached while getting focused element")
                throw AccessibilityError.timeout
            }

            if let element = getRobustFocusedElement() {
                return element
            }

            logger.warning("Attempt \(attempt) failed to get focused element")

            if attempt < maxRetries {
                // Brief synchronous wait (we're on MainActor, can't use async sleep here)
                Thread.sleep(forTimeInterval: 0.1)
            }
        }

        return nil
    }

    /// Gets the focused element using robust detection
    /// Entirely MainActor-isolated - no crossing to other actors
    private func getRobustFocusedElement() -> AXUIElement? {
        AXUIElementSafeWrapper.withMemoryCleanup {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                return nil
            }

            guard let appElement = AXUIElementSafeWrapper.createApplicationElement(
                processIdentifier: frontApp.processIdentifier
            ) else {
                return nil
            }

            // Try to get focused UI element directly
            if let focusedRef = AXUIElementSafeWrapper.getAttributeValue(
                from: appElement,
                attribute: kAXFocusedUIElementAttribute
            ) {
                let focusedElement = focusedRef as! AXUIElement
                if AXUIElementSafeWrapper.isValidElement(focusedElement) {
                    return focusedElement
                }
            }

            // Fall back to searching in focused window
            if let windowRef = AXUIElementSafeWrapper.getAttributeValue(
                from: appElement,
                attribute: kAXFocusedWindowAttribute
            ) {
                let windowElement = windowRef as! AXUIElement
                if AXUIElementSafeWrapper.isValidElement(windowElement) {
                    return self.findFocusedInTree(windowElement, depth: 0, maxDepth: 20, visited: [])
                }
            }

            return nil
        }
    }

    /// Recursively finds a focused text element in the UI tree
    private func findFocusedInTree(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        visited: Set<AXElementID>
    ) -> AXUIElement? {
        guard depth < maxDepth else { return nil }

        let elementID = AXElementID(element)
        guard !visited.contains(elementID) else { return nil }

        // Check if this element has text attributes
        if AXUIElementSafeWrapper.getAttributeValue(from: element, attribute: kAXValueAttribute) != nil ||
           AXUIElementSafeWrapper.getAttributeValue(from: element, attribute: kAXSelectedTextRangeAttribute) != nil {
            // Verify it's the focused element
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let appElement = AXUIElementSafeWrapper.createApplicationElement(processIdentifier: frontApp.processIdentifier),
               let focusedRef = AXUIElementSafeWrapper.getAttributeValue(from: appElement, attribute: kAXFocusedUIElementAttribute) {
                let focusedElement = focusedRef as! AXUIElement
                if Unmanaged.passUnretained(element).toOpaque() == Unmanaged.passUnretained(focusedElement).toOpaque() {
                    return element
                }
            }
        }

        // Search children
        let children = AXUIElementSafeWrapper.getChildren(from: element)
        var newVisited = visited
        newVisited.insert(elementID)

        for child in children {
            if let found = findFocusedInTree(child, depth: depth + 1, maxDepth: maxDepth, visited: newVisited) {
                return found
            }
        }

        return nil
    }

    // MARK: - Element Info Updates

    private func updateElementInfo(_ info: ElementInfo) {
        let isSelf = info.applicationBundleId == Bundle.main.bundleIdentifier

        // Update application info
        applicationInfo = ApplicationInfo(name: info.applicationName, bundleId: info.applicationBundleId)

        guard info.frame.isValid, !isSelf else {
            return
        }

        // Check if we should update frame
        if !shouldUpdateFrame {
            shouldUpdateFrame = previousRect != info.frame
        }

        // Check if we should update text
        if !shouldUpdateText {
            shouldUpdateText = previousText != info.text
        }

        // Update based on frame changes
        if shouldUpdateFrame && previousRect == info.frame {
            elementInfo = info.withFrame(frame: info.frame)
            shouldUpdateFrame = false
        } else if previousRect != info.frame {
            elementInfo = nil
        }

        // Update based on text changes
        if shouldUpdateText && previousText == info.text {
            elementInfo = info.withText(text: info.text)
            shouldUpdateText = false
        } else if previousText != info.text {
            elementInfo = nil
        }

        previousRect = info.frame
        previousText = info.text
    }

    private func clearElementInfo() {
        elementInfo = nil
        applicationInfo = .empty
    }

    // MARK: - Permissions

    private var isProcessTrusted: Bool {
        AXIsProcessTrusted()
    }

    private func showPromptIfNeeded() {
        guard shouldDisplayPermissionPrompt else { return }

        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        shouldDisplayPermissionPrompt = false
    }

    private func displayRestartIfNeeded() {
        guard shouldDisplayRestartPrompt else { return }
        shouldDisplayRestartPrompt = false
        displayRestart()
    }

    private func displayRestart() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = """
        Accessibility permissions have been updated, and a restart is required \
        for them to fully take effect. Please quit and reopen the app.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
        restartApp()
    }

    private func restartApp() {
        guard let bundlePath = Bundle.main.bundlePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return
        }

        let script = """
        sleep 0.5
        open "\(bundlePath)"
        """
        _ = Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", script])
        NSApp.terminate(nil)
    }
}

// MARK: - ElementInfo Extensions

extension ElementInfo {
    func withFrame(frame: CGRect) -> ElementInfo {
        ElementInfo(
            text: text,
            applicationName: applicationName,
            applicationBundleId: applicationBundleId,
            frame: frame,
            elementIdentifier: elementIdentifier,
            isSelectedText: isSelectedText
        )
    }

    func withText(text: String) -> ElementInfo {
        ElementInfo(
            text: text,
            applicationName: applicationName,
            applicationBundleId: applicationBundleId,
            frame: frame,
            elementIdentifier: elementIdentifier,
            isSelectedText: isSelectedText
        )
    }
}

// MARK: - CGRect Extension

extension CGRect {
    var isValid: Bool {
        origin.x != .infinity &&
        origin.y != .infinity &&
        size.width != 0 &&
        size.height != 0
    }
}
