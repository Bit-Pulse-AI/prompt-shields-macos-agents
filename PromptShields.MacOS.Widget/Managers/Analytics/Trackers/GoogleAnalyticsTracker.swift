import Foundation
import os

// MARK: - Google Analytics Tracker

/// Google Analytics 4 tracker using Measurement Protocol
/// Sends events to GA4 via HTTP requests
actor GoogleAnalyticsTracker: AnalyticsTracker {
    // MARK: - Properties

    nonisolated let identifier = TrackerType.googleAnalytics.rawValue

    private var _isEnabled: Bool = true
    nonisolated var isEnabled: Bool {
        // Return cached value for nonisolated access
        true
    }

    private let measurementId: String
    private let apiSecret: String
    private let clientId: String
    private var userProperties: AnalyticsUserProperties?
    private var eventQueue: [QueuedEvent] = []
    private var flushTask: Task<Void, Never>?

    private let configuration: AnalyticsConfiguration
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "GoogleAnalytics"
    )

    private let baseURL = "https://www.google-analytics.com/mp/collect"

    // MARK: - Types

    private struct QueuedEvent: Sendable {
        let event: AnalyticsEvent
        let timestamp: Date
    }

    private struct GA4Event: Codable {
        let name: String
        let params: [String: AnyCodable]
    }

    private struct GA4Payload: Codable {
        let clientId: String
        let userId: String?
        let userProperties: [String: GA4UserProperty]?
        let events: [GA4Event]

        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case userId = "user_id"
            case userProperties = "user_properties"
            case events
        }
    }

    private struct GA4UserProperty: Codable {
        let value: String
    }

    // MARK: - Initialization

    init(
        measurementId: String,
        apiSecret: String,
        configuration: AnalyticsConfiguration = .default
    ) {
        self.measurementId = measurementId
        self.apiSecret = apiSecret
        self.configuration = configuration

        // Generate or retrieve persistent client ID
        if let storedClientId = UserDefaults.standard.string(forKey: "analytics_client_id") {
            self.clientId = storedClientId
        } else {
            let newClientId = UUID().uuidString
            UserDefaults.standard.set(newClientId, forKey: "analytics_client_id")
            self.clientId = newClientId
        }

        self._isEnabled = configuration.isEnabled
    }

    // MARK: - AnalyticsTracker

    func initialize() async {
        logger.info("Google Analytics tracker initialized")
        logger.info("Measurement ID: \(self.measurementId)")
        logger.info("Client ID: \(self.clientId)")

        // Start periodic flush
        startPeriodicFlush()
    }

    func track(_ event: AnalyticsEvent) async {
        guard _isEnabled else {
            logger.debug("Tracker disabled, skipping event: \(event.name)")
            return
        }

        let queuedEvent = QueuedEvent(event: event, timestamp: Date())
        eventQueue.append(queuedEvent)

        if configuration.isDebugMode {
            logger.debug("Queued event: \(event.name) - \(event.parameters)")
        }

        // Flush if batch size reached
        if eventQueue.count >= configuration.maxBatchSize {
            await flush()
        }
    }

    func setUserProperties(_ properties: AnalyticsUserProperties) async {
        self.userProperties = properties
        logger.debug("User properties updated")
    }

    func reset() async {
        eventQueue.removeAll()
        userProperties = nil
        logger.info("Google Analytics tracker reset")
    }

    func flush() async {
        guard !eventQueue.isEmpty else { return }

        let eventsToSend = eventQueue
        eventQueue.removeAll()

        await sendEvents(eventsToSend)
    }

    func setEnabled(_ enabled: Bool) async {
        _isEnabled = enabled
        logger.info("Google Analytics tracker \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Private Methods

    private func startPeriodicFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.configuration.flushInterval ?? 30))
                await self?.flush()
            }
        }
    }

    private func sendEvents(_ events: [QueuedEvent]) async {
        guard !events.isEmpty else { return }

        let ga4Events = events.map { queuedEvent -> GA4Event in
            var params: [String: AnyCodable] = [:]

            for (key, value) in queuedEvent.event.parameters {
                params[key] = AnyCodable(value)
            }

            // Add engagement time (required for GA4)
            params["engagement_time_msec"] = AnyCodable(100)

            return GA4Event(name: queuedEvent.event.name, params: params)
        }

        var userPropertiesDict: [String: GA4UserProperty]?
        if let props = userProperties {
            userPropertiesDict = [:]
            for (key, value) in props.asDictionary {
                userPropertiesDict?[key] = GA4UserProperty(value: value)
            }
        }

        let payload = GA4Payload(
            clientId: clientId,
            userId: userProperties?.userId,
            userProperties: userPropertiesDict,
            events: ga4Events
        )

        // Build URL with query parameters
        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "measurement_id", value: measurementId),
            URLQueryItem(name: "api_secret", value: apiSecret)
        ]

        guard let url = urlComponents.url else {
            logger.error("Failed to build GA4 URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(payload)

            if configuration.isDebugMode {
                if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
                    logger.debug("Sending GA4 payload: \(jsonString)")
                }
            }

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 {
                    logger.debug("Successfully sent \(events.count) events to GA4")
                } else {
                    logger.warning("GA4 returned status code: \(httpResponse.statusCode)")
                }
            }
        } catch {
            logger.error("Failed to send events to GA4: \(error.localizedDescription)")

            // Re-queue failed events (with limit to prevent infinite growth)
            if eventQueue.count < configuration.maxBatchSize * 3 {
                eventQueue.append(contentsOf: events)
            }
        }
    }
}

// MARK: - AnyCodable Helper

/// Helper type for encoding heterogeneous dictionary values
struct AnyCodable: Codable, Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Factory

extension GoogleAnalyticsTracker {
    /// Creates a Google Analytics tracker with configuration from environment or constants
    static func createDefault() -> GoogleAnalyticsTracker {
        // These should be configured in your app's constants or environment
        let measurementId = Const.Analytics.googleMeasurementId
        let apiSecret = Const.Analytics.googleApiSecret

        #if DEBUG
        return GoogleAnalyticsTracker(
            measurementId: measurementId,
            apiSecret: apiSecret,
            configuration: .debug
        )
        #else
        return GoogleAnalyticsTracker(
            measurementId: measurementId,
            apiSecret: apiSecret,
            configuration: .default
        )
        #endif
    }
}

