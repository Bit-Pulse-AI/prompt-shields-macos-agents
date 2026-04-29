import Foundation
import os

// PolicyClient — fetches active policy instances from the AI-SPM dashboard
// and caches them locally. The PolicyEnforcer reads from the cache on every
// keystroke (must be cheap), so this layer's only job is to keep the cache
// fresh.
//
// Refresh cadence: 5 minutes. Manual refresh on app foreground or when the
// user changes their tenant. The cache is in-memory only — restart fetches
// from scratch — because policy state is tenant-sensitive and we don't want
// stale rules sitting on disk after a logout.

protocol PolicyTransport: Sendable {
    /// Performs `GET /api/policies` (or the configured equivalent) against
    /// the AI-SPM dashboard. Returns the bundle of active instances and
    /// their referenced templates.
    func fetchActivePolicies() async throws -> ActivePoliciesResponse

    /// Posts a single violation to `/api/policies/violations`. Implementations
    /// should debounce / batch as appropriate.
    func reportViolation(_ violation: PolicyViolation) async throws
}

/// Errors surfaced by the transport layer. Kept narrow so the enforcer
/// can decide whether to fail-open (allow the action) or fail-closed
/// (block until policy is known).
enum PolicyClientError: Error, Sendable {
    case unconfigured
    case network(Error)
    case decoding(Error)
    case http(status: Int, body: String?)
}

@MainActor
final class PolicyClient: ObservableObject {
    @Published private(set) var instances: [PolicyInstance] = []
    @Published private(set) var templates: [String: PolicyTemplate] = [:]
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var lastError: PolicyClientError?

    private let transport: PolicyTransport
    private let refreshInterval: TimeInterval
    private var refreshTask: Task<Void, Never>?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "PolicyClient"
    )

    init(transport: PolicyTransport, refreshInterval: TimeInterval = 300) {
        self.transport = transport
        self.refreshInterval = refreshInterval
    }

    // MARK: - Lifecycle

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.refreshInterval ?? 300))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Force a fresh fetch. Call from app-foreground or after a tenant change.
    func refresh() async {
        do {
            let response = try await transport.fetchActivePolicies()
            instances = response.instances
            templates = Dictionary(uniqueKeysWithValues: response.templates.map { ($0.id, $0) })
            lastRefreshed = Date()
            lastError = nil
            logger.debug("Loaded \(response.instances.count) active policies")
        } catch let err as PolicyClientError {
            lastError = err
            logger.error("Policy fetch failed: \(String(describing: err))")
        } catch {
            lastError = .network(error)
            logger.error("Policy fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reads

    /// Returns the instances that apply to the given app id (e.g. "chatgpt").
    /// Empty `applicationIds` on an instance means "applies to every app",
    /// matching the dashboard semantics.
    func instances(forApp appId: String) -> [PolicyInstance] {
        instances.filter { $0.appliesToApp(id: appId) }
    }

    func template(for instance: PolicyInstance) -> PolicyTemplate? {
        templates[instance.templateId]
    }

    // MARK: - Reporting (forwarded so callers don't need the transport)

    func reportViolation(_ violation: PolicyViolation) async {
        do {
            try await transport.reportViolation(violation)
        } catch {
            logger.error("Violation report failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - HTTP transport

/// Concrete `PolicyTransport` that talks to a real AI-SPM dashboard URL.
/// `bearerTokenProvider` is optional; tenants that authenticate via cookie
/// session can pass nil and rely on the URLSession shared cookie storage.
struct HTTPPolicyTransport: PolicyTransport {
    let baseURL: URL
    let bearerTokenProvider: (@Sendable () async -> String?)?

    init(baseURL: URL, bearerTokenProvider: (@Sendable () async -> String?)? = nil) {
        self.baseURL = baseURL
        self.bearerTokenProvider = bearerTokenProvider
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    func fetchActivePolicies() async throws -> ActivePoliciesResponse {
        let url = baseURL.appendingPathComponent("api/policies")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        if let provider = bearerTokenProvider, let token = await provider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PolicyClientError.network(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8)
            throw PolicyClientError.http(status: http.statusCode, body: body)
        }
        do {
            return try Self.decoder.decode(ActivePoliciesResponse.self, from: data)
        } catch {
            throw PolicyClientError.decoding(error)
        }
    }

    func reportViolation(_ violation: PolicyViolation) async throws {
        let url = baseURL.appendingPathComponent("api/policies/violations")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let provider = bearerTokenProvider, let token = await provider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10
        request.httpBody = try Self.encoder.encode(violation)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PolicyClientError.network(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw PolicyClientError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }
    }
}
