import Foundation
import os

// MARK: - PostHog Tracker

/// PostHog analytics tracker using the Capture API
/// Sends events to PostHog for product analytics and feature flags
actor PostHogTracker: AnalyticsTracker {
    // MARK: - Properties

    nonisolated let identifier = TrackerType.postHog.rawValue

    private var _isEnabled: Bool = true
    nonisolated var isEnabled: Bool { true }

    private let apiKey: String
    private let host: String
    private let distinctId: String
    private var userProperties: AnalyticsUserProperties?
    private var eventQueue: [QueuedEvent] = []
    private var flushTask: Task<Void, Never>?

    private let configuration: AnalyticsConfiguration
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "PostHog"
    )

    // MARK: - Types

    private struct QueuedEvent: Sendable {
        let event: AnalyticsEvent
        let timestamp: Date
    }

    private struct PostHogEvent: Codable {
        let event: String
        let properties: [String: AnyCodable]
        let timestamp: String
        let distinctId: String

        enum CodingKeys: String, CodingKey {
            case event
            case properties
            case timestamp
            case distinctId = "distinct_id"
        }
    }

    private struct PostHogBatch: Codable {
        let apiKey: String
        let batch: [PostHogEvent]

        enum CodingKeys: String, CodingKey {
            case apiKey = "api_key"
            case batch
        }
    }

    private struct PostHogIdentify: Codable {
        let apiKey: String
        let distinctId: String
        let properties: [String: AnyCodable]
        let set: [String: AnyCodable]

        enum CodingKeys: String, CodingKey {
            case apiKey = "api_key"
            case distinctId = "distinct_id"
            case properties = "$set"
            case set = "$set_once"
        }
    }

    // MARK: - Initialization

    init(
        apiKey: String,
        host: String = "https://app.posthog.com",
        configuration: AnalyticsConfiguration = .default
    ) {
        self.apiKey = apiKey
        self.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.configuration = configuration

        // Generate or retrieve persistent distinct ID
        if let storedId = UserDefaults.standard.string(forKey: "posthog_distinct_id") {
            self.distinctId = storedId
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "posthog_distinct_id")
            self.distinctId = newId
        }

        self._isEnabled = configuration.isEnabled
    }

    // MARK: - AnalyticsTracker

    func initialize() async {
        logger.info("PostHog tracker initialized")
        logger.info("Host: \(self.host)")
        logger.info("Distinct ID: \(self.distinctId)")

        // Start periodic flush
        startPeriodicFlush()
    }

    func track(_ event: AnalyticsEvent) async {
        guard _isEnabled else {
            logger.debug("Tracker disabled, skipping event: \(event.name)")
            return
        }

        guard !apiKey.isEmpty else {
            logger.debug("PostHog API key not configured, skipping event: \(event.name)")
            return
        }

        let queuedEvent = QueuedEvent(event: event, timestamp: Date())
        eventQueue.append(queuedEvent)

        if configuration.isDebugMode {
            logger.debug("Queued event: \(event.name)")
        }

        // Flush if batch size reached
        if eventQueue.count >= configuration.maxBatchSize {
            await flush()
        }
    }

    func setUserProperties(_ properties: AnalyticsUserProperties) async {
        self.userProperties = properties

        // Send identify call to PostHog
        await identify(properties)
        logger.debug("User properties updated")
    }

    func reset() async {
        eventQueue.removeAll()
        userProperties = nil

        // Generate new distinct ID on reset (e.g., logout)
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "posthog_distinct_id")

        logger.info("PostHog tracker reset with new distinct ID")
    }

    func flush() async {
        guard !eventQueue.isEmpty else { return }

        let eventsToSend = eventQueue
        eventQueue.removeAll()

        await sendEvents(eventsToSend)
    }

    func setEnabled(_ enabled: Bool) async {
        _isEnabled = enabled
        logger.info("PostHog tracker \(enabled ? "enabled" : "disabled")")
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

    private func identify(_ properties: AnalyticsUserProperties) async {
        guard !apiKey.isEmpty else { return }

        let url = URL(string: "\(host)/identify")!

        var setProps: [String: AnyCodable] = [:]
        var setOnceProps: [String: AnyCodable] = [:]

        // Set properties (can be updated)
        for (key, value) in properties.asDictionary {
            setProps[key] = AnyCodable(value)
        }

        // Set once properties (only set on first identification)
        setOnceProps["first_seen"] = AnyCodable(ISO8601DateFormatter().string(from: Date()))

        let identifyPayload = PostHogIdentify(
            apiKey: apiKey,
            distinctId: properties.userId ?? distinctId,
            properties: setProps,
            set: setOnceProps
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(identifyPayload)

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    logger.debug("PostHog identify successful")
                } else {
                    logger.warning("PostHog identify returned status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            logger.error("Failed to send PostHog identify: \(error.localizedDescription)")
        }
    }

    private func sendEvents(_ events: [QueuedEvent]) async {
        guard !events.isEmpty, !apiKey.isEmpty else { return }

        let isoFormatter = ISO8601DateFormatter()

        let postHogEvents = events.map { queuedEvent -> PostHogEvent in
            var properties: [String: AnyCodable] = [:]

            // Add event parameters
            for (key, value) in queuedEvent.event.parameters {
                properties[key] = AnyCodable(value)
            }

            // Add standard PostHog properties
            properties["$lib"] = AnyCodable("promptshields-macos")
            properties["$lib_version"] = AnyCodable(App.version)
            properties["$os"] = AnyCodable("macOS")
            properties["$os_version"] = AnyCodable(ProcessInfo.processInfo.operatingSystemVersionString)

            // Add user properties if available
            if let userProps = userProperties {
                if let userId = userProps.userId {
                    properties["$user_id"] = AnyCodable(userId)
                }
                properties["subscription_tier"] = AnyCodable(userProps.subscriptionTier ?? "free")
            }

            return PostHogEvent(
                event: queuedEvent.event.name,
                properties: properties,
                timestamp: isoFormatter.string(from: queuedEvent.timestamp),
                distinctId: userProperties?.userId ?? distinctId
            )
        }

        let batch = PostHogBatch(apiKey: apiKey, batch: postHogEvents)

        let url = URL(string: "\(host)/batch")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(batch)

            if configuration.isDebugMode {
                if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
                    logger.debug("Sending PostHog batch: \(jsonString)")
                }
            }

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    logger.debug("Successfully sent \(events.count) events to PostHog")
                } else {
                    logger.warning("PostHog returned status code: \(httpResponse.statusCode)")
                }
            }
        } catch {
            logger.error("Failed to send events to PostHog: \(error.localizedDescription)")

            // Re-queue failed events (with limit to prevent infinite growth)
            if eventQueue.count < configuration.maxBatchSize * 3 {
                eventQueue.append(contentsOf: events)
            }
        }
    }
}

// MARK: - Factory

extension PostHogTracker {
    /// Creates a PostHog tracker with configuration from constants
    static func createDefault() -> PostHogTracker {
        #if DEBUG
        return PostHogTracker(
            apiKey: postHogApiKey,
            host: postHogHost,
            configuration: .debug
        )
        #else
        return PostHogTracker(
            apiKey: postHogApiKey,
            host: postHogHost,
            configuration: .default
        )
        #endif
    }
}

