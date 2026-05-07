import Foundation
import os

// HTTP client for the supplementary telemetry streams that supplement
// the existing PolicyClient feed. Dashboard URL is read from the same
// `aiSPMDashboardURL` UserDefaults key — when that's empty the client
// is a NullTransport noop, so existing tenants without an AI-SPM
// dashboard configured see zero behaviour change.
//
// Three endpoints currently supported:
//   - POST /api/people/me            (PersonSyncRequest)
//   - POST /api/applications/auto-discovery   (AutoDiscoveryRequest)
//   - POST /api/usage-events         (UsageEventBatch)
//
// All requests fail open: a network error logs and drops the event.
// Promptly's UX never blocks on telemetry succeeding.

protocol TelemetryTransport: Sendable {
    func syncPerson(_ request: PersonSyncRequest) async throws
    func reportAutoDiscovery(_ request: AutoDiscoveryRequest) async throws
    func reportUsageBatch(_ batch: UsageEventBatch) async throws
}

enum TelemetryTransportError: Error, Sendable {
    case unconfigured
    case network(Error)
    case http(status: Int, body: String?)
}

@MainActor
final class TelemetryClient {
    static let shared = TelemetryClient()

    private var transport: TelemetryTransport
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "TelemetryClient"
    )

    private init() {
        self.transport = NullTelemetryTransport()
    }

    /// Wired by MainApp.configurePolicyClient at boot. Same dashboard URL
    /// as the policy stream — kept in lockstep so a tenant either gets
    /// both or neither.
    func setTransport(_ transport: TelemetryTransport) {
        self.transport = transport
    }

    // MARK: - Person sync

    func syncPerson(_ request: PersonSyncRequest) async {
        do {
            try await transport.syncPerson(request)
            logger.debug("synced person \(request.email, privacy: .private)")
        } catch {
            logger.debug("person sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Auto-discovery (throttled)

    private var autoDiscoverySeen: [String: Date] = [:]
    private let autoDiscoveryWindow: TimeInterval = 3600  // 1h per (app, person)

    /// Reports an auto-discovered app, throttled to once per hour per
    /// (promptlyAppId, observedByAuth0Sub) pair. Calling more often than
    /// that is a noop.
    func reportAutoDiscovery(_ request: AutoDiscoveryRequest) async {
        let key = "\(request.promptlyAppId)|\(request.observedByAuth0Sub ?? "anon")"
        if let last = autoDiscoverySeen[key],
           Date().timeIntervalSince(last) < autoDiscoveryWindow {
            return
        }
        autoDiscoverySeen[key] = Date()
        do {
            try await transport.reportAutoDiscovery(request)
            logger.debug("auto-discovered \(request.promptlyAppId, privacy: .public)")
        } catch {
            logger.debug("auto-discovery failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Usage events (batched)

    func flushUsageBatch(_ batch: UsageEventBatch) async {
        guard !batch.events.isEmpty else { return }
        do {
            try await transport.reportUsageBatch(batch)
            logger.debug("flushed \(batch.events.count) usage events")
        } catch {
            logger.debug("usage batch failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - HTTP transport

struct HTTPTelemetryTransport: TelemetryTransport {
    let baseURL: URL
    let bearerTokenProvider: (@Sendable () async -> String?)?

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    init(baseURL: URL, bearerTokenProvider: (@Sendable () async -> String?)? = nil) {
        self.baseURL = baseURL
        self.bearerTokenProvider = bearerTokenProvider
    }

    func syncPerson(_ request: PersonSyncRequest) async throws {
        try await post(path: "api/people/me", body: request)
    }

    func reportAutoDiscovery(_ request: AutoDiscoveryRequest) async throws {
        try await post(path: "api/applications/auto-discovery", body: request)
    }

    func reportUsageBatch(_ batch: UsageEventBatch) async throws {
        try await post(path: "api/usage-events", body: batch)
    }

    private func post<T: Encodable>(path: String, body: T) async throws {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let provider = bearerTokenProvider, let token = await provider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10
        request.httpBody = try Self.encoder.encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TelemetryTransportError.network(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw TelemetryTransportError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }
    }
}

struct NullTelemetryTransport: TelemetryTransport {
    func syncPerson(_ request: PersonSyncRequest) async throws {}
    func reportAutoDiscovery(_ request: AutoDiscoveryRequest) async throws {}
    func reportUsageBatch(_ batch: UsageEventBatch) async throws {}
}
