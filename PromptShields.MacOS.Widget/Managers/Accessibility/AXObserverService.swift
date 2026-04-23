import AppKit
import ApplicationServices
import os

// AXObserverService — event-driven replacement for the old 500ms polling
// loop. One instance per observed app (pid). Subscribing to a notification
// on an element fires `onNotification` on MainActor the moment the event
// happens — no polling.
//
// This is the primitive that the rest of the Grammarly-style detection
// stack (FocusTracker, AccessibilityManagerImpl) is built on.
//
// Callback flow:
//   C callback (observerCallback)
//     └── Unmanaged.fromOpaque(refcon) -> AXObserverService
//           └── MainActor.assumeIsolated { onNotification?(...) }
//
// Because we register the observer with CFRunLoopGetMain() the callback
// already fires on the main thread, so assumeIsolated is safe.

@MainActor
final class AXObserverService {
    // MARK: - State

    private let pid: pid_t
    private let observer: AXObserver
    private var subscribed: Set<SubscriptionKey> = []

    /// Called whenever any subscribed notification fires. Arguments:
    /// the notification name (e.g. `kAXValueChangedNotification`) and the
    /// element that fired it.
    var onNotification: ((String, AXUIElement) -> Void)?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "AXObserverService"
    )

    // MARK: - Init / teardown

    init?(pid: pid_t) {
        self.pid = pid

        var observerRef: AXObserver?
        let result = AXObserverCreate(pid, Self.callback, &observerRef)
        guard result == .success, let observerRef else {
            return nil
        }
        self.observer = observerRef

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    deinit {
        // Run loop source is owned by the observer; dropping the observer
        // cleans it up. We intentionally don't call AXObserverRemoveNotification
        // for every subscription — letting AXObserver go out of scope releases
        // everything.
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    // MARK: - Subscribe / unsubscribe

    /// Subscribe to a notification on an element. Returns true if the
    /// subscription succeeded (or was already registered).
    @discardableResult
    func subscribe(_ notification: String, on element: AXUIElement) -> Bool {
        let key = SubscriptionKey(notification: notification, element: element)
        guard !subscribed.contains(key) else { return true }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(
            observer,
            element,
            notification as CFString,
            refcon
        )

        switch result {
        case .success, .notificationAlreadyRegistered:
            subscribed.insert(key)
            return true
        case .invalidUIElement, .invalidUIElementObserver:
            // Element went away between focus-change and subscribe. Normal.
            return false
        case .cannotComplete, .failure:
            logger.debug("subscribe \(notification, privacy: .public) failed: \(String(describing: result), privacy: .public)")
            return false
        default:
            logger.debug("subscribe \(notification, privacy: .public) unexpected result: \(String(describing: result), privacy: .public)")
            return false
        }
    }

    func unsubscribe(_ notification: String, on element: AXUIElement) {
        let key = SubscriptionKey(notification: notification, element: element)
        guard subscribed.contains(key) else { return }
        AXObserverRemoveNotification(observer, element, notification as CFString)
        subscribed.remove(key)
    }

    /// Drop every per-element subscription. Used when the focused element
    /// changes and we want to stop listening to the old one.
    func unsubscribeAll(except keep: Set<String> = []) {
        for key in subscribed where !keep.contains(key.notification) {
            AXObserverRemoveNotification(observer, key.element, key.notification as CFString)
        }
        subscribed = subscribed.filter { keep.contains($0.notification) }
    }

    // MARK: - C callback trampoline

    private static let callback: AXObserverCallback = { _, element, notificationRef, refcon in
        guard let refcon else { return }
        let service = Unmanaged<AXObserverService>.fromOpaque(refcon).takeUnretainedValue()
        let notification = notificationRef as String
        // Callback fires on the main run loop (we registered against
        // CFRunLoopGetMain), so MainActor isolation is already correct.
        MainActor.assumeIsolated {
            service.onNotification?(notification, element)
        }
    }

    // MARK: - Subscription key

    /// Uniqueness key for a (notification, element) subscription pair.
    /// AXUIElement isn't Hashable out of the box, so we bridge through
    /// `CFHash` — good enough to dedupe within this observer.
    private struct SubscriptionKey: Hashable {
        let notification: String
        let element: AXUIElement

        static func == (lhs: SubscriptionKey, rhs: SubscriptionKey) -> Bool {
            lhs.notification == rhs.notification
                && CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(notification)
            hasher.combine(CFHash(element))
        }
    }
}
