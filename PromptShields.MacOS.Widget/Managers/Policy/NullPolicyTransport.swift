import Foundation

/// No-op transport used when no AI-SPM dashboard is configured for the
/// current tenant. Returning an empty bundle means PolicyEnforcer never
/// fires — Promptly continues to operate purely on local heuristics
/// (PIIDetector / Redaction-first). Once a dashboard URL is provided,
/// swap this for `HTTPPolicyTransport` via the dependency container.
struct NullPolicyTransport: PolicyTransport {
    func fetchActivePolicies() async throws -> ActivePoliciesResponse {
        ActivePoliciesResponse(
            instances: [],
            templates: [],
            snapshotAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    func reportViolation(_ violation: PolicyViolation) async throws {
        // Drop on the floor — nowhere to send.
    }
}
