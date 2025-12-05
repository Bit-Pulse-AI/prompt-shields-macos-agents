import Foundation

// MARK: - Analytics Tracker Protocol

/// Protocol defining the interface for analytics trackers
/// Following Interface Segregation Principle - clean, focused interface
protocol AnalyticsTracker: Sendable {
    /// Unique identifier for this tracker
    var identifier: String { get }

    /// Whether the tracker is currently enabled
    var isEnabled: Bool { get }

    /// Initialize the tracker
    func initialize() async

    /// Track an analytics event
    /// - Parameter event: The event to track
    func track(_ event: AnalyticsEvent) async

    /// Set user properties for the tracker
    /// - Parameter properties: User properties to set
    func setUserProperties(_ properties: AnalyticsUserProperties) async

    /// Reset the tracker (e.g., on logout)
    func reset() async

    /// Flush any pending events
    func flush() async

    /// Enable or disable the tracker
    func setEnabled(_ enabled: Bool) async
}

// MARK: - Default Implementations

extension AnalyticsTracker {
    func flush() async {
        // Default implementation does nothing
    }
}

// MARK: - Tracker Configuration

/// Configuration for analytics trackers
struct AnalyticsConfiguration: Sendable {
    let isEnabled: Bool
    let isDebugMode: Bool
    let flushInterval: TimeInterval
    let maxBatchSize: Int

    static let `default` = AnalyticsConfiguration(
        isEnabled: true,
        isDebugMode: false,
        flushInterval: 30.0,
        maxBatchSize: 20
    )

    #if DEBUG
    static let debug = AnalyticsConfiguration(
        isEnabled: true,
        isDebugMode: true,
        flushInterval: 5.0,
        maxBatchSize: 5
    )
    #endif
}

// MARK: - Tracker Registry

/// Registry for managing available tracker types
enum TrackerType: String, CaseIterable, Sendable {
    case googleAnalytics = "google_analytics"
    case postHog = "posthog"
    case firebase = "firebase"
    case console = "console" // For debugging

    var displayName: String {
        switch self {
        case .googleAnalytics: return "Google Analytics"
        case .postHog: return "PostHog"
        case .firebase: return "Firebase"
        case .console: return "Console Logger"
        }
    }
}
