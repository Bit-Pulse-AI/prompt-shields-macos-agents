import AppKit
import ApplicationServices
import os

// FocusTracker — the Grammarly-style event-driven entry point for text
// detection. Replaces the old 500ms polling loop in AccessibilityManager.
//
// Responsibilities:
//   1. Watch NSWorkspace frontmost-app changes. For each app that takes
//      focus, tear down the previous AXObserverService and create a new
//      one scoped to the new app's pid.
//   2. Subscribe to app-level focus-change notifications
//      (kAXFocusedUIElementChangedNotification,
//       kAXFocusedWindowChangedNotification) so we're told the moment a
//      text field gains focus.
//   3. When a new editable element takes focus, subscribe to
//      kAXValueChangedNotification and kAXSelectedTextChangedNotification
//      on that element. Debounce rapid value changes ~150ms so we don't
//      thrash on every keystroke.
//   4. Emit `onElementInfo(ElementInfo?)` whenever the detected state
//      changes (focused + debounced text, or nil when focus leaves).
//
// All AXUIElement work happens on the main actor. The AXObserver C
// callback is registered on CFRunLoopGetMain(), so notifications arrive
// on the main thread.

@MainActor
final class FocusTracker {
    // MARK: - Callbacks

    /// Called whenever the focused editable element changes or its text
    /// is updated (after debouncing). `nil` means no editable element is
    /// currently focused in any monitored app.
    var onElementInfo: ((ElementInfo?) -> Void)?

    // MARK: - State

    private let textFieldDetector: TextFieldDetector
    private var currentObserver: AXObserverService?
    private var currentPID: pid_t?
    private var currentAppElement: AXUIElement?
    private var currentFocusedElement: AXUIElement?
    private var currentInfo: ElementInfo?
    private var debounceTask: Task<Void, Never>?
    private var workspaceObserver: NSObjectProtocol?

    private let valueDebounceInterval: Duration = .milliseconds(150)

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "FocusTracker"
    )

    init(textFieldDetector: TextFieldDetector) {
        self.textFieldDetector = textFieldDetector
    }

    // MARK: - Lifecycle

    /// Start observing. Attaches to the currently-frontmost app and the
    /// NSWorkspace notification stream.
    func start() {
        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self else { return }
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                MainActor.assumeIsolated {
                    self.attachTo(app: app)
                }
            }
        }

        if let front = NSWorkspace.shared.frontmostApplication {
            attachTo(app: front)
        }
    }

    /// Tear everything down. Call when monitoring is disabled or on deinit.
    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        currentObserver = nil
        currentPID = nil
        currentAppElement = nil
        currentFocusedElement = nil
        if currentInfo != nil {
            currentInfo = nil
            onElementInfo?(nil)
        }
    }

    // No deinit. NotificationCenter observers held by NSWorkspace are
    // weakly-referenced when added via the block-based API on macOS 11+,
    // and the FocusTracker is owned by AccessibilityManagerImpl for the
    // lifetime of the app — there's no realistic detach path between
    // start() and process termination. Removing the explicit cleanup keeps
    // Swift 6's nonisolated-deinit rule happy.

    // MARK: - App attach / detach

    private func attachTo(app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid > 0, pid != currentPID else { return }

        // Don't observe our own app.
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            detach()
            return
        }

        detach()

        guard let appElement = AXUIElementSafeWrapper.createApplicationElement(processIdentifier: pid) else {
            logger.debug("could not create app element for pid=\(pid)")
            return
        }

        guard let observer = AXObserverService(pid: pid) else {
            logger.debug("could not create AXObserver for pid=\(pid)")
            return
        }

        observer.onNotification = { [weak self] notification, element in
            self?.handleNotification(notification, element: element)
        }

        // App-level subscriptions: tell us when focus changes inside this app.
        observer.subscribe(kAXFocusedUIElementChangedNotification as String, on: appElement)
        observer.subscribe(kAXFocusedWindowChangedNotification as String, on: appElement)
        observer.subscribe(kAXMainWindowChangedNotification as String, on: appElement)

        self.currentPID = pid
        self.currentObserver = observer
        self.currentAppElement = appElement

        // Seed: check the currently-focused element at attach time so we
        // don't wait for the first focus-change event.
        resolveAndObserveFocusedElement()

        // Auto-discovery: if this app isn't in our MonitoredApps catalog
        // AND it isn't a known browser, surface it to AI-SPM so the
        // dashboard can flag the shadow AI tool. The TelemetryClient
        // throttles to once/hour/(app,user) — calling here on every
        // focus event is safe.
        Task { @MainActor in
            await maybeReportAutoDiscovery(app: app)
        }

        DetectionTrace.log("focus_attach",
                           bundleId: app.bundleIdentifier,
                           note: "pid=\(pid)")
    }

    /// Reports an unrecognised AI surface to AI-SPM. Conservative: skips
    /// our own app, system processes, the macOS shell, and known-good
    /// non-AI tools. The dashboard side is idempotent so a false positive
    /// here just adds noise to the auto-discovery queue, never breaks
    /// anything.
    private func maybeReportAutoDiscovery(app: NSRunningApplication) async {
        let bundleId = app.bundleIdentifier ?? ""
        guard !bundleId.isEmpty else { return }

        // Skip Promptly itself, Finder/Dock/Spotlight, browsers (we'll
        // catch web-based AI via URL — separate ticket), and any app
        // already in MonitoredApps.
        let skipPrefixes = [
            "ai.bit-pulse.PromptShields",
            "com.apple.dock", "com.apple.finder", "com.apple.Spotlight",
            "com.apple.controlcenter", "com.apple.systemuiserver"
        ]
        if skipPrefixes.contains(where: { bundleId.hasPrefix($0) }) { return }
        if AXUIElementSafeWrapper.isBrowser(bundleId: bundleId) { return }
        if MonitoredAppsRegistry.shared.enabledNativeApp(bundleId: bundleId) != nil { return }

        let appName = app.localizedName ?? bundleId
        let request = AutoDiscoveryRequest(
            promptlyAppId: "shadow-\(bundleId)",
            componentName: appName,
            observedSource: bundleId,
            observedByAuth0Sub: nil,    // populated server-side from the auth header eventually
            observedAt: ISO8601DateFormatter().string(from: Date())
        )
        await TelemetryClient.shared.reportAutoDiscovery(request)
    }

    private func detach() {
        debounceTask?.cancel()
        debounceTask = nil
        currentObserver = nil
        currentPID = nil
        currentAppElement = nil
        currentFocusedElement = nil
        if currentInfo != nil {
            currentInfo = nil
            onElementInfo?(nil)
        }
    }

    // MARK: - Notification handling

    private func handleNotification(_ notification: String, element: AXUIElement) {
        switch notification {
        case kAXFocusedUIElementChangedNotification as String,
             kAXFocusedWindowChangedNotification as String,
             kAXMainWindowChangedNotification as String:
            resolveAndObserveFocusedElement()

        case kAXValueChangedNotification as String,
             kAXSelectedTextChangedNotification as String:
            scheduleDebouncedUpdate()

        case kAXUIElementDestroyedNotification as String:
            // The focused element went away (modal closed, field removed,
            // etc). Clear immediately and wait for the next focus event.
            currentFocusedElement = nil
            if currentInfo != nil {
                currentInfo = nil
                onElementInfo?(nil)
            }

        default:
            break
        }
    }

    /// Resolve the current focused element (using the same heuristics as
    /// the old polling path), subscribe to per-element notifications, and
    /// publish initial text.
    private func resolveAndObserveFocusedElement() {
        guard let observer = currentObserver, let appElement = currentAppElement else { return }

        let resolved = findFocusedEditableElement(in: appElement)

        // If focus is on a non-editable element (menu, toolbar, etc), treat
        // that as "no text field in focus" but DON'T drop the app observer.
        guard let focused = resolved else {
            currentFocusedElement = nil
            if currentInfo != nil {
                currentInfo = nil
                onElementInfo?(nil)
            }
            return
        }

        // If the focused element is the same element we're already
        // subscribed to, don't re-subscribe.
        if let current = currentFocusedElement, CFEqual(current, focused) {
            scheduleDebouncedUpdate()
            return
        }

        // Unsubscribe the old element's value/selection/destroyed notifications.
        if let previous = currentFocusedElement {
            observer.unsubscribe(kAXValueChangedNotification as String, on: previous)
            observer.unsubscribe(kAXSelectedTextChangedNotification as String, on: previous)
            observer.unsubscribe(kAXUIElementDestroyedNotification as String, on: previous)
        }

        currentFocusedElement = focused

        observer.subscribe(kAXValueChangedNotification as String, on: focused)
        observer.subscribe(kAXSelectedTextChangedNotification as String, on: focused)
        observer.subscribe(kAXUIElementDestroyedNotification as String, on: focused)

        // Publish initial info immediately so the overlay appears as soon
        // as focus lands on an editable element.
        publishCurrentInfo()
    }

    // MARK: - Debounced text extraction

    private func scheduleDebouncedUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(for: self.valueDebounceInterval)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.publishCurrentInfo()
            }
        }
    }

    private func publishCurrentInfo() {
        guard let focused = currentFocusedElement else {
            if currentInfo != nil {
                currentInfo = nil
                onElementInfo?(nil)
            }
            return
        }

        guard AXUIElementSafeWrapper.isValidElement(focused) else {
            DetectionTrace.log("invalid_element_publish")
            currentFocusedElement = nil
            if currentInfo != nil {
                currentInfo = nil
                onElementInfo?(nil)
            }
            return
        }

        do {
            var info = try textFieldDetector.getAXElementOrSelectionInfo(focused)
            let role = AXUIElementSafeWrapper.getRole(from: focused) ?? "?"
            let editable = AXUIElementSafeWrapper.isEditable(focused)

            // Augment with the page URL when the focus is inside a
            // browser. Used by AI-SPM to populate evidence.urlHost on
            // PolicyViolation envelopes — gives the dashboard a
            // per-domain view of where prompts were typed.
            let url = Self.findFocusedURL(startingFrom: focused)
            if let url, info.focusedURL != url {
                info = ElementInfo(
                    text: info.text,
                    applicationName: info.applicationName,
                    applicationBundleId: info.applicationBundleId,
                    frame: info.frame,
                    elementIdentifier: info.elementIdentifier,
                    isSelectedText: info.isSelectedText,
                    focusedURL: url
                )
            }

            DetectionTrace.log("text_field_info",
                               bundleId: info.applicationBundleId,
                               role: role,
                               editable: editable,
                               textLen: info.text.count)

            if info != currentInfo {
                currentInfo = info
                onElementInfo?(info)
            }
        } catch {
            DetectionTrace.log("extract_error",
                               note: String(describing: error).prefix(80).description)
        }
    }

    /// Walks up the AX parent chain until we hit an `AXWebArea`, then
    /// reads its `AXURL` attribute. Returns the URL string when found,
    /// nil for native fields. Bounded depth so a malformed tree can't
    /// hang the poller.
    @MainActor
    private static func findFocusedURL(startingFrom element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        var depth = 0
        let maxDepth = 25

        while let node = current, depth < maxDepth {
            if let role = AXUIElementSafeWrapper.getRole(from: node), role == "AXWebArea" {
                if let raw = AXUIElementSafeWrapper.getAttributeValue(from: node, attribute: "AXURL") {
                    if let url = raw as? URL { return url.absoluteString }
                    if let s = raw as? String { return s }
                    if let nsurl = raw as? NSURL { return nsurl.absoluteString }
                }
                // Some Chromium frames expose the URL via AXDocumentURL instead.
                if let raw = AXUIElementSafeWrapper.getAttributeValue(from: node, attribute: "AXDocumentURL") {
                    if let s = raw as? String { return s }
                    if let url = raw as? URL { return url.absoluteString }
                }
                return nil
            }

            guard let parentRef = AXUIElementSafeWrapper.getAttributeValue(from: node, attribute: kAXParentAttribute),
                  let parent = AXUIElementSafeWrapper.asAXUIElement(parentRef) else {
                return nil
            }
            current = parent
            depth += 1
        }
        return nil
    }

    // MARK: - Focused element resolution

    /// Given an app element, find the focused editable element using the
    /// same browser-aware logic as the previous polling path.
    private func findFocusedEditableElement(in appElement: AXUIElement) -> AXUIElement? {
        AXUIElementSafeWrapper.withMemoryCleanup {
            let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            let isBrowser = AXUIElementSafeWrapper.isBrowser(bundleId: bundleId)

            // Try focused UI element.
            if let focusedRef = AXUIElementSafeWrapper.getAttributeValue(
                from: appElement,
                attribute: kAXFocusedUIElementAttribute
            ), let focused = AXUIElementSafeWrapper.asAXUIElement(focusedRef) {
                if AXUIElementSafeWrapper.isValidElement(focused) {
                    if isBrowser {
                        if AXUIElementSafeWrapper.isWebContent(focused) {
                            if let editable = AXUIElementSafeWrapper.findEditableElementInWebContent(focused) {
                                return editable
                            }
                        }
                        if AXUIElementSafeWrapper.isEditable(focused)
                            || AXUIElementSafeWrapper.isTextInputElement(focused) {
                            return focused
                        }
                        if let editable = AXUIElementSafeWrapper.findEditableElementInWebContent(focused) {
                            return editable
                        }
                    } else {
                        if AXUIElementSafeWrapper.isEditable(focused)
                            || AXUIElementSafeWrapper.isTextInputElement(focused) {
                            return focused
                        }
                    }
                }
            }

            return nil
        }
    }
}
