import os
import SwiftUI
import Foundation
import ApplicationServices
import AppKit

// MARK: - Monitoring State

/// Represents the current state of accessibility monitoring
enum MonitoringState: Equatable, Sendable {
    /// Monitoring is disabled (default state)
    case disabled
    /// Monitoring is enabled and running
    case enabled
    /// Monitoring is paused (e.g., screen locked)
    case paused
    /// Waiting for accessibility permissions
    case awaitingPermissions
}

// MARK: - Accessibility Manager

/// Manages accessibility operations for detecting and interacting with focused text fields.
/// Uses MainActor isolation for all AXUIElement operations to ensure Swift 6 compliance.
///
/// **Permission Flow:**
/// 1. App starts with monitoring OFF by default
/// 2. User must be logged in to enable monitoring
/// 3. When user enables monitoring, we check for accessibility permissions
/// 4. If permissions not granted, we prompt and wait
/// 5. Only after permissions are granted does monitoring actually start
@MainActor
final class AccessibilityManagerImpl: ObservableObject {
    // MARK: - Published Properties

    @Published var elementInfo: ElementInfo?
    @Published var applicationInfo: ApplicationInfo = .empty
    @Published private(set) var monitoringState: MonitoringState = .disabled
    @Published private(set) var hasAccessibilityPermission: Bool = false

    /// When true, element info updates are paused (e.g., when action menu is open)
    @Published var isInteractionActive: Bool = false

    /// Convenience property for backward compatibility
    var isActive: Bool {
        monitoringState == .enabled
    }

    // MARK: - Private Properties

    // Slow safety-net heartbeat. Notifications from the AXObserver are the
    // primary signal; the heartbeat only covers the edge case where a
    // notification is missed (e.g. observer was installed moments before
    // an app spawned a new process).
    private let safetyHeartbeatInterval: TimeInterval = 5.0
    private var heartbeatTask: Task<Void, Never>?
    private var permissionCheckTask: Task<Void, Never>?
    private let textFieldDetector = TextFieldDetector()
    private lazy var focusTracker: FocusTracker = {
        let tracker = FocusTracker(textFieldDetector: textFieldDetector)
        tracker.onElementInfo = { [weak self] info in
            guard let self = self else { return }
            if let info {
                self.updateElementInfo(info)
            } else {
                self.clearElementInfo()
            }
        }
        return tracker
    }()
    private var previousText: String?
    private var previousRect: CGRect?
    private var savedMonitoringState: MonitoringState?
    private var hasPromptedForPermissions = false
    private var permissionCheckCount = 0
    private let maxPermissionChecks = 3
    /// Preserved element info while interaction is active
    private var preservedElementInfo: ElementInfo?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AccessibilityManagerImpl.self)
    )

    // MARK: - Initialization

    init() {
        // Initial permission check - may be stale immediately after launch
        hasAccessibilityPermission = AXIsProcessTrusted()
        setupSystemLockObservers()

        // Schedule additional permission checks after a delay
        // This handles the case where permissions are granted but not yet visible
        // (e.g., after app reinstall with existing system permissions)
        startInitialPermissionPolling()

        logger.debug("AccessibilityManager initialized. Initial permissions: \(self.hasAccessibilityPermission)")
    }

    /// Polls for permission state several times at startup to catch delayed permission visibility
    private func startInitialPermissionPolling() {
        permissionCheckTask = Task { @MainActor [weak self] in
            // Check multiple times over the first few seconds
            let checkIntervals: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(5)]

            for interval in checkIntervals {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: interval)

                guard let self = self else { return }

                let currentState = AXIsProcessTrusted()

                // Only update if permission was granted (never downgrade without user action)
                if currentState && !self.hasAccessibilityPermission {
                    self.logger.debug("Accessibility permissions detected after delay")
                    self.hasAccessibilityPermission = true

                    // If we were waiting for permissions, start monitoring
                    if self.monitoringState == .awaitingPermissions {
                        self.startMonitoring()
                    }
                }

                // If already granted, no need to keep checking
                if self.hasAccessibilityPermission {
                    self.logger.debug("Permissions confirmed, stopping initial polling")
                    return
                }
            }
        }
    }

    deinit {
        heartbeatTask?.cancel()
        permissionCheckTask?.cancel()
    }

    // MARK: - Public API

    /// Enables monitoring if permissions are granted, otherwise requests them
    /// Should only be called when user is logged in
    func enableMonitoring() {
        logger.debug("Enable monitoring requested")

        // Check current permission state
        hasAccessibilityPermission = AXIsProcessTrusted()

        if hasAccessibilityPermission {
            startMonitoring()
            Analytics.trackAsync(.monitoringEnabled)
        } else {
            requestAccessibilityPermissions()
        }
    }

    /// Disables monitoring and clears any detected elements
    func disableMonitoring() {
        logger.debug("Disable monitoring requested")
        stopMonitoring()
        monitoringState = .disabled
        Analytics.trackAsync(.monitoringDisabled)
    }

    /// Toggles monitoring state
    func toggleMonitoring() {
        if monitoringState == .enabled {
            disableMonitoring()
        } else {
            enableMonitoring()
        }
    }

    /// Pauses element info updates while user is interacting with action menu
    /// The current element info is preserved and will be used until interaction ends
    func pauseForInteraction() {
        guard !isInteractionActive else { return }
        isInteractionActive = true
        preservedElementInfo = elementInfo
        // Lock the registry to prevent clearing the current element
        AXElementRegistry.shared.lock()
        logger.debug("Pausing monitoring for user interaction")
    }

    /// Resumes element info updates after user finishes interacting with action menu
    func resumeFromInteraction() {
        guard isInteractionActive else { return }
        isInteractionActive = false
        preservedElementInfo = nil
        // Unlock the registry to allow normal operation
        AXElementRegistry.shared.unlock()
        logger.debug("Resuming monitoring after user interaction")
        }

    /// Refreshes the permission state without prompting.
    /// Call this when the app becomes active or when you suspect permissions may have changed.
    func refreshPermissionState() {
        let wasGranted = hasAccessibilityPermission
        let currentState = AXIsProcessTrusted()

        logger.debug("Refreshing permission state: was=\(wasGranted), now=\(currentState)")

        hasAccessibilityPermission = currentState

        // If permissions were just granted and we're waiting, start monitoring
        if !wasGranted && currentState && monitoringState == .awaitingPermissions {
            logger.debug("Permissions granted, starting monitoring")
            Analytics.trackAsync(.accessibilityPermissionGranted)
            startMonitoring()
        }

        // If permissions were revoked while monitoring, pause
        if wasGranted && !currentState && monitoringState == .enabled {
            logger.debug("Permissions revoked, pausing monitoring")
            monitoringState = .awaitingPermissions
            clearElementInfo()
        }
    }

    /// Forces a fresh check of accessibility permissions from the system.
    /// This bypasses any caching and queries the TCC database directly.
    func forcePermissionCheck() -> Bool {
        // AXIsProcessTrusted() queries the TCC database each time
        let granted = AXIsProcessTrusted()
        hasAccessibilityPermission = granted

        logger.debug("Force permission check result: \(granted)")
        return granted
    }

    // MARK: - Permission Handling

    private func requestAccessibilityPermissions() {
        logger.debug("Requesting accessibility permissions")
        monitoringState = .awaitingPermissions
        permissionCheckCount = 0

        // Track permission request
        Analytics.trackAsync(.accessibilityPermissionRequested)

        // Show the system permission prompt
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        hasPromptedForPermissions = true

        // Start polling for permission grant
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        permissionCheckTask?.cancel()
        permissionCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                let granted = AXIsProcessTrusted()
                self.hasAccessibilityPermission = granted

                if granted {
                    self.logger.debug("Accessibility permissions granted")
                    Analytics.trackAsync(.accessibilityPermissionGranted)
                    self.startMonitoring()
                    Analytics.trackAsync(.monitoringEnabled)
                    return
                }

                self.permissionCheckCount += 1

                // After several checks, stop polling and wait for user action
                if self.permissionCheckCount > 30 { // ~15 seconds
                    self.logger.debug("Permission polling timeout, waiting for user action")
                    Analytics.trackAsync(.accessibilityPermissionDenied)
                    return
                }

                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Monitoring Control

    /// Starts event-driven monitoring (Grammarly-style):
    /// - Installs an AXObserver on the frontmost app via `FocusTracker`.
    /// - Subscribes to focus / value / selection notifications.
    /// - Runs a slow (5s) safety-net heartbeat to recover from dropped
    ///   notifications.
    private func startMonitoring() {
        guard hasAccessibilityPermission else {
            logger.debug("Cannot start monitoring without permissions")
            return
        }

        monitoringState = .enabled
        logger.debug("Starting event-driven accessibility monitoring")

        focusTracker.start()
        startSafetyHeartbeat()
    }

    private func stopMonitoring() {
        focusTracker.stop()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        clearElementInfo()
        logger.debug("Stopped accessibility monitoring")
    }

    /// Slow heartbeat that runs every `safetyHeartbeatInterval` seconds. Its
    /// only job is to recover from missed notifications: it checks permission
    /// status and asks the focus tracker to re-resolve the current focus.
    /// Real-time updates come from the AXObserver — this is belt-and-suspenders.
    private func startSafetyHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                try? await Task.sleep(for: .seconds(self.safetyHeartbeatInterval))
                guard !Task.isCancelled else { return }

                guard self.monitoringState == .enabled, !self.isInteractionActive else { continue }

                // Verify permissions are still valid.
                guard AXIsProcessTrusted() else {
                    self.logger.debug("Lost accessibility permissions")
                    self.hasAccessibilityPermission = false
                    self.monitoringState = .awaitingPermissions
                    self.clearElementInfo()
                    return
                }

                // Ping the tracker — it'll re-attach to the current frontmost
                // app (noop if already attached) and re-resolve the focused
                // element. Cheap and covers the edge case where we missed a
                // focus-change notification.
                self.focusTracker.start()

                DetectionTrace.log("heartbeat", note: "safety-net")
            }
        }
    }

    // MARK: - System Observers

    private func setupSystemLockObservers() {
        let dnc = DistributedNotificationCenter.default()
        let nc = NotificationCenter.default

        // Screen lock/unlock observers
        dnc.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.monitoringState == .enabled {
                    self.savedMonitoringState = .enabled
                    self.monitoringState = .paused
                    self.clearElementInfo()
                    self.logger.debug("Screen locked, pausing monitoring")
                }
            }
        }

        dnc.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.savedMonitoringState == .enabled {
                    self.monitoringState = .enabled
                    self.savedMonitoringState = nil
                    self.logger.debug("Screen unlocked, resuming monitoring")
                }
            }
        }

        nc.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.refreshPermissionState()
            }
        }

        nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
                guard let self = self else { return }
                if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier == Bundle.main.bundleIdentifier {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    self?.refreshPermissionState()
                }
            }
        }
    }

    // MARK: - Element Info Updates

    private func updateElementInfo(_ info: ElementInfo) {
        let isSelf = info.applicationBundleId == Bundle.main.bundleIdentifier

        // Update application info
        applicationInfo = ApplicationInfo(name: info.applicationName, bundleId: info.applicationBundleId)

        // PS-13: honor the per-app disable toggle from Settings. We only
        // short-circuit when the user has explicitly disabled a MonitoredApp
        // whose bundleId matches — unknown apps/browsers keep their default
        // behavior. URL-level gating (disable "ChatGPT" while on chat.openai.com
        // in a browser) would require ElementInfo to carry the focused URL;
        // see docs/investigations/ps-13-monitored-apps.md.
        let isDisabledByUser = MonitoredAppsRegistry.shared.isDisabled(bundleId: info.applicationBundleId)

        guard info.frame.isValid, !isSelf, !isDisabledByUser else {
            DetectionTrace.log("gated",
                               bundleId: info.applicationBundleId,
                               note: isSelf ? "isSelf" : (isDisabledByUser ? "userDisabled" : "invalidFrame"))
            return
        }

        // Simple update - just set the new info
        if previousRect != info.frame || previousText != info.text {
            // Track text field detection if this is a new detection
            if elementInfo == nil {
                if info.isSelectedText {
                    Analytics.trackAsync(.selectedTextDetected(application: info.applicationName, length: info.text.count))
                } else {
                    Analytics.trackAsync(.textFieldDetected(application: info.applicationName))
            }
            }
            elementInfo = info
        }

        previousRect = info.frame
        previousText = info.text
    }

    private func clearElementInfo() {
        if elementInfo != nil {
            Analytics.trackAsync(.textFieldLost)
        }
        elementInfo = nil
        applicationInfo = .empty
        previousRect = nil
        previousText = nil
    }

    // MARK: - Legacy API (for backward compatibility)

    /// Legacy method - use enableMonitoring() instead
    func startTimer() {
        enableMonitoring()
    }

    /// Legacy method - use disableMonitoring() instead
    func stopTimer() {
        disableMonitoring()
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
