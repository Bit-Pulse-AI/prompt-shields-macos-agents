import Foundation
import os

// MARK: - Analytics Manager

/// Central manager for all analytics tracking
/// Orchestrates multiple trackers and provides a unified API
/// Following Open/Closed Principle - open for extension (new trackers), closed for modification
@MainActor
final class AnalyticsManager: ObservableObject {
    // MARK: - Singleton

    static let shared = AnalyticsManager()

    // MARK: - Published Properties

    @Published private(set) var isEnabled: Bool = true
    @Published private(set) var activeTrackerCount: Int = 0

    // MARK: - Private Properties

    private var trackers: [any AnalyticsTracker] = []
    private var userProperties: AnalyticsUserProperties?
    private var isInitialized = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "AnalyticsManager"
    )

    // MARK: - Initialization

    private init() {
        // Load enabled state from UserDefaults
        isEnabled = UserDefaults.standard.object(forKey: "analytics_enabled") as? Bool ?? true
    }

    // MARK: - Setup

    /// Initialize the analytics manager with default trackers
    func initialize() async {
        guard !isInitialized else {
            logger.warning("AnalyticsManager already initialized")
            return
        }

        logger.info("Initializing AnalyticsManager...")

        // Add default trackers
        #if DEBUG
        // In debug mode, add console tracker for visibility
        await addTracker(ConsoleAnalyticsTracker())
        #endif

        // Add Google Analytics for general analytics
        await addTracker(GoogleAnalyticsTracker.createDefault())

        // Add PostHog for product analytics
        await addTracker(PostHogTracker.createDefault())

        // Add Firebase for performance and crash reporting
        await addTracker(FirebaseTracker.createDefault())

        isInitialized = true
        logger.info("AnalyticsManager initialized with \(self.trackers.count) tracker(s)")

        // Track app launch
        await track(.appLaunched)
    }

    // MARK: - Tracker Management

    /// Add a new tracker
    /// - Parameter tracker: The tracker to add
    func addTracker(_ tracker: any AnalyticsTracker) async {
        // Check if tracker already exists
        if trackers.contains(where: { $0.identifier == tracker.identifier }) {
            logger.warning("Tracker \(tracker.identifier) already registered")
            return
        }

        await tracker.initialize()
        trackers.append(tracker)
        activeTrackerCount = trackers.count

        // Set user properties if already configured
        if let properties = userProperties {
            await tracker.setUserProperties(properties)
        }

        logger.info("Added tracker: \(tracker.identifier)")
    }

    /// Remove a tracker by identifier
    /// - Parameter identifier: The tracker identifier to remove
    func removeTracker(identifier: String) async {
        trackers.removeAll { $0.identifier == identifier }
        activeTrackerCount = trackers.count
        logger.info("Removed tracker: \(identifier)")
    }

    /// Remove a tracker by type
    /// - Parameter type: The tracker type to remove
    func removeTracker(type: TrackerType) async {
        await removeTracker(identifier: type.rawValue)
    }

    /// Get a tracker by identifier
    /// - Parameter identifier: The tracker identifier
    /// - Returns: The tracker if found
    func getTracker(identifier: String) -> (any AnalyticsTracker)? {
        trackers.first { $0.identifier == identifier }
    }

    /// Get all active trackers
    var allTrackers: [any AnalyticsTracker] {
        trackers
    }

    // MARK: - Tracking

    /// Track an analytics event
    /// - Parameter event: The event to track
    func track(_ event: AnalyticsEvent) async {
        guard isEnabled else {
            logger.debug("Analytics disabled, skipping event: \(event.name)")
            return
        }

        // Send to all trackers concurrently
        await withTaskGroup(of: Void.self) { group in
            for tracker in trackers {
                group.addTask {
                    await tracker.track(event)
                }
            }
        }
    }

    /// Track an event with a simple fire-and-forget call
    /// Use this for convenience when you don't need to await
    nonisolated func trackAsync(_ event: AnalyticsEvent) {
        Task { @MainActor in
            await track(event)
        }
    }

    // MARK: - User Properties

    /// Set user properties for all trackers
    /// - Parameter properties: The user properties to set
    func setUserProperties(_ properties: AnalyticsUserProperties) async {
        self.userProperties = properties

        await withTaskGroup(of: Void.self) { group in
            for tracker in trackers {
                group.addTask {
                    await tracker.setUserProperties(properties)
                }
            }
        }

        logger.info("User properties updated across all trackers")
    }

    /// Update user properties with new values
    func updateUserProperties(
        userId: String? = nil,
        email: String? = nil,
        subscriptionTier: String? = nil,
        teamId: String? = nil
    ) async {
        let properties = AnalyticsUserProperties(
            userId: userId ?? userProperties?.userId,
            email: email ?? userProperties?.email,
            subscriptionTier: subscriptionTier ?? userProperties?.subscriptionTier,
            teamId: teamId ?? userProperties?.teamId
        )
        await setUserProperties(properties)
    }

    // MARK: - Control

    /// Enable or disable all analytics tracking
    /// - Parameter enabled: Whether analytics should be enabled
    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "analytics_enabled")

        await withTaskGroup(of: Void.self) { group in
            for tracker in trackers {
                group.addTask {
                    await tracker.setEnabled(enabled)
                }
            }
        }

        logger.info("Analytics \(enabled ? "enabled" : "disabled")")
    }

    /// Toggle analytics on/off
    func toggleEnabled() async {
        await setEnabled(!isEnabled)
    }

    /// Reset all trackers (e.g., on logout)
    func reset() async {
        userProperties = nil

        await withTaskGroup(of: Void.self) { group in
            for tracker in trackers {
                group.addTask {
                    await tracker.reset()
                }
            }
        }

        logger.info("All trackers reset")
    }

    /// Flush all pending events
    func flush() async {
        await withTaskGroup(of: Void.self) { group in
            for tracker in trackers {
                group.addTask {
                    await tracker.flush()
                }
            }
        }

        logger.debug("All trackers flushed")
    }
}

// MARK: - Convenience Extensions

extension AnalyticsManager {
    /// Track a custom event
    func trackCustom(name: String, parameters: [String: String] = [:]) async {
        await track(.custom(name: name, parameters: parameters))
    }

    /// Track an error
    func trackError(_ error: Error, domain: String = "app") async {
        let nsError = error as NSError
        await track(.errorOccurred(
            domain: domain,
            code: String(nsError.code),
            message: error.localizedDescription
        ))
    }

    /// Track a performance metric
    func trackPerformance(name: String, value: Double, unit: String = "ms") async {
        await track(.performanceMetric(name: name, value: value, unit: unit))
    }

    /// Measure and track execution time of an async operation
    func measureAsync<T>(name: String, operation: () async throws -> T) async rethrows -> T {
        let start = Date()
        let result = try await operation()
        let duration = Date().timeIntervalSince(start) * 1000 // Convert to ms
        await trackPerformance(name: name, value: duration)
        return result
    }
}

// MARK: - Global Convenience

/// Global convenience function for tracking events
/// Usage: Analytics.track(.appLaunched)
enum Analytics {
    @MainActor
    static func track(_ event: AnalyticsEvent) async {
        await AnalyticsManager.shared.track(event)
    }

    /// Fire-and-forget tracking
    @MainActor static func trackAsync(_ event: AnalyticsEvent) {
        AnalyticsManager.shared.trackAsync(event)
    }
}
