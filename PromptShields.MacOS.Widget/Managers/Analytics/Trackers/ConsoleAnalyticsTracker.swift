import Foundation
import os

// MARK: - Console Analytics Tracker

/// Debug tracker that logs events to the console
/// Useful for development and debugging
actor ConsoleAnalyticsTracker: AnalyticsTracker {
    // MARK: - Properties

    nonisolated let identifier = TrackerType.console.rawValue

    private var _isEnabled: Bool = true
    nonisolated var isEnabled: Bool { true }

    private var userProperties: AnalyticsUserProperties?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "ConsoleAnalytics"
    )

    // MARK: - AnalyticsTracker

    func initialize() async {
        logger.info("📊 Console Analytics Tracker initialized")
    }

    func track(_ event: AnalyticsEvent) async {
        guard _isEnabled else { return }

        let params = event.parameters
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")

        logger.info("📊 [\(event.category)] \(event.name) - {\(params)}")
    }

    func setUserProperties(_ properties: AnalyticsUserProperties) async {
        self.userProperties = properties

        let propsString = properties.asDictionary
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")

        logger.info("📊 User properties set: {\(propsString)}")
    }

    func reset() async {
        userProperties = nil
        logger.info("📊 Console Analytics Tracker reset")
    }

    func flush() async {
        logger.debug("📊 Console tracker flush (no-op)")
    }

    func setEnabled(_ enabled: Bool) async {
        _isEnabled = enabled
        logger.info("📊 Console tracker \(enabled ? "enabled" : "disabled")")
    }
}


