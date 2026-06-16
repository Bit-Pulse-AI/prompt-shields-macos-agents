import Foundation

// Wire-format types for the macOS widget → atlas.ai prompt-telemetry
// stream: POST {atlas}/api/v1/telemetry/prompt-events with an X-API-Key
// header. Contract source of truth:
// atlas.ai backend/app/schemas/telemetry.py (Pydantic, extra="forbid" —
// any unknown JSON key rejects that row, so send EXACTLY these fields).
//
// PRIVACY CONTRACT: there is no field in these types that can carry
// prompt text. Hash + metadata only. Keep it that way.
//
// MUST stay Foundation-only: Scripts/atlas-encoder-tests.sh compiles this
// file standalone with swiftc as the CLI test path.

/// One row for grc.prompt_events. Nil optionals are omitted from the JSON
/// (synthesized encodeIfPresent), which the endpoint treats as null/default.
struct AtlasPromptEvent: Codable, Sendable, Equatable {
    /// Always "macos_widget" for events from this app.
    let source: String
    /// "activity" (prompt counted) or "violation" (policy/PII hit).
    let eventKind: String
    /// Monitored-app registry id (chatgpt | claude | …) or shadow-<bundleId>.
    let appId: String?
    /// SHA-256 hex of the prompt, exactly 64 lowercase hex chars, or nil.
    /// The server hard-rejects rows with malformed hashes — the encoder
    /// drops invalid hashes to nil instead of losing the whole event.
    let promptHash: String?
    /// allowed | logged | redacted | flagged | blocked, or nil.
    let action: String?
    /// low | medium | high | critical, or nil.
    let severity: String?
    /// PII/detector category → match count (counts must be >= 1).
    let piiCategories: [String: Int]?
    /// Auth0 sub of the user, when known.
    let userExternalId: String?
    /// Unused by macOS today; kept for wire-compat.
    let sessionId: String?
    /// Client-side rollup multiplier, 1–10000 (server-enforced).
    let occurrences: Int
    /// ISO-8601 timestamp of the (last) observation.
    let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case source, action, severity, occurrences
        case eventKind = "event_kind"
        case appId = "app_id"
        case promptHash = "prompt_hash"
        case piiCategories = "pii_categories"
        case userExternalId = "user_external_id"
        case sessionId = "session_id"
        case occurredAt = "occurred_at"
    }
}

/// Request envelope: {"events": [...]}, 1–500 events per request.
struct AtlasPromptEventBatch: Codable, Sendable, Equatable {
    let events: [AtlasPromptEvent]
}
