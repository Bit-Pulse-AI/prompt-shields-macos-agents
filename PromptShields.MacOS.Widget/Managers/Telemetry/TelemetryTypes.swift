import Foundation

// Wire-format types for the macOS → AI-SPM telemetry stream.
// Mirrors the dashboard's CRUD endpoints documented in
// ai-spm-dashboard/docs/ai-spm-crud-plan.md. Keep these in sync with the
// TS counterparts; the dashboard's route handlers re-export the canonical
// type from `lib/entities/types.ts`.

// MARK: - People sync

/// POST /api/people/me — upserts a Person record from the macOS app.
/// `auth0Sub` is the join key (Auth0 `sub` claim); falls back to email
/// dedupe on the server. Sent on first login + when the user updates
/// their profile.
struct PersonSyncRequest: Codable, Sendable, Equatable {
    let auth0Sub: String
    let email: String
    let componentName: String   // "First Last" — display name
    let role: String?
    /// Optional client-known department; admin can override on the dashboard.
    let organizationalUnitId: String?
    /// Promptly version that emitted this — useful for migration triage.
    let appVersion: String
}

// MARK: - Application auto-discovery

/// POST /api/applications/auto-discovery — called when Promptly observes
/// the user focusing an unrecognised AI app. Idempotent on the dashboard
/// side: existing shadow Application gets its `lastObservedAt` bumped;
/// a new one is created with `deploymentStatus="Shadow"`.
struct AutoDiscoveryRequest: Codable, Sendable, Equatable {
    /// Stable id Promptly uses internally (MonitoredApp.id when known,
    /// else a synthesized "shadow-<bundleHash>").
    let promptlyAppId: String
    /// Human-readable app name shown in the dashboard until an admin
    /// edits it (e.g. "Cursor", "ai.cursor.io").
    let componentName: String
    /// Original macOS bundle id or browser URL host that triggered this.
    let observedSource: String
    /// Auth0 sub of the person who triggered detection — links the auto-
    /// discovered Application back to a Person on the dashboard side.
    let observedByAuth0Sub: String?
    /// ISO timestamp of the observation.
    let observedAt: String
}

// MARK: - Usage events

/// Daily rollup row for `POST /api/usage-events`. Promptly aggregates
/// events in-memory per (auth0Sub, promptlyAppId, day) and flushes the
/// rollup batch on app deactivate / quit so we don't spam the network on
/// every keystroke.
struct UsageEvent: Codable, Sendable, Equatable, Hashable {
    /// `YYYY-MM-DD` in the user's local timezone.
    let day: String
    let auth0Sub: String?
    let promptlyAppId: String   // chatgpt | claude | notion | …
    let promptCount: Int        // accepted suggestions + chat turns + clean evaluations
    let blockedCount: Int       // policy `.block` decisions
    let redactedCount: Int      // policy `.redact` decisions
    let flaggedCount: Int       // policy `.flag` decisions
    /// First and last observation timestamps within the day (ISO).
    let firstSeen: String
    let lastSeen: String
}

struct UsageEventBatch: Codable, Sendable {
    let events: [UsageEvent]
    let appVersion: String
}

// MARK: - Tour engagement (Sprint D+)

/// Daily rollup of guided-tour interactions per (day, person, tour).
/// Sent to `POST /api/tour-engagement`. Lets the dashboard surface a
/// WalkMe-style "engagement funnel" — how many users started each tour,
/// how many completed, where they bailed.
struct TourEngagementEvent: Codable, Sendable, Equatable, Hashable {
    /// `YYYY-MM-DD` in the user's local timezone.
    let day: String
    let auth0Sub: String?
    let tourId: String              // dashboard-intro | chat-intro | …
    /// Total times this tour entered step 0 today.
    let startCount: Int
    /// Total times the user clicked "Got it" / "Next →" past the last step.
    let completionCount: Int
    /// Dismissals broken out by reason ("skip_button" | "esc" | "click_outside").
    let dismissalCounts: [String: Int]
    /// Sum of completion durations (seconds) today — divide by completionCount
    /// for the average. 0 if no completions.
    let totalDurationSec: Double
    /// Per-step exit counts (key = step index as string, value = times the user
    /// dismissed *while on that step*). Surfaces where tours get abandoned.
    let stepDismissalCounts: [String: Int]
    let firstSeen: String
    let lastSeen: String
}

struct TourEngagementBatch: Codable, Sendable {
    let events: [TourEngagementEvent]
    let appVersion: String
}
