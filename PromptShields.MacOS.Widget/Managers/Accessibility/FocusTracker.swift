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

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

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

        DetectionTrace.log("focus_attach",
                           bundleId: app.bundleIdentifier,
                           note: "pid=\(pid)")
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
            let info = try textFieldDetector.getAXElementOrSelectionInfo(focused)
            let role = AXUIElementSafeWrapper.getRole(from: focused) ?? "?"
            let editable = AXUIElementSafeWrapper.isEditable(focused)
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
