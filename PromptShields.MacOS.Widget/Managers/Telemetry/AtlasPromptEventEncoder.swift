import Foundation

// AtlasPromptEventEncoder — pure translation from the app's existing
// telemetry types (UsageEvent rollups, PolicyViolation posts) to the
// atlas.ai prompt-event wire format. No I/O, no state, no AppKit: this
// file is compiled standalone by Scripts/atlas-encoder-tests.sh.
//
// Mapping contract: atlas.ai
// docs/superpowers/specs/2026-06-11-prompt-telemetry-design.md
// ("macOS widget" client section), with two deliberate local decisions:
//   - actionTaken == .evaluated is DROPPED (not mapped to a null-action
//     violation): evaluated ticks are clean-prompt denominators already
//     counted via promptCount → activity/allowed; a violation row per
//     clean prompt would corrupt violation_rate and double-count.
//   - a malformed promptHash is dropped to nil rather than sent: the
//     server skips entire rows with bad hashes, and the event metadata
//     is worth keeping even when the hash is unusable.
//
// PRIVACY: PolicyViolation.evidence (detectorOutput / matchedPattern)
// can contain fragments of the user's prompt. This encoder NEVER reads
// `evidence` — see `assertNoContentFields` in the test harness, which
// pushes a sentinel through every field that could leak and asserts it
// is absent from the encoded JSON.

enum AtlasPromptEventEncoder {
    static let source = "macos_widget"
    static let maxOccurrences = 10_000
    static let maxBatchSize = 500
    private static let hashPattern = "^[0-9a-f]{64}$"

    // MARK: - UsageEvent rollups

    /// One daily rollup row fans out into up to four wire events, one per
    /// non-zero counter. Blocked/flagged are violations; prompt/redacted
    /// are activity (redaction is treated as resolved activity, matching
    /// the Safari client).
    static func events(from usage: UsageEvent) -> [AtlasPromptEvent] {
        let mappings: [(count: Int, kind: String, action: String)] = [
            (usage.promptCount, "activity", "allowed"),
            (usage.redactedCount, "activity", "redacted"),
            (usage.flaggedCount, "violation", "flagged"),
            (usage.blockedCount, "violation", "blocked"),
        ]
        return mappings.compactMap { mapping in
            guard mapping.count > 0 else { return nil }
            return AtlasPromptEvent(
                source: source,
                eventKind: mapping.kind,
                appId: usage.promptlyAppId,
                promptHash: nil,
                action: mapping.action,
                severity: nil,
                piiCategories: nil,
                userExternalId: usage.auth0Sub,
                sessionId: nil,
                occurrences: min(mapping.count, maxOccurrences),
                occurredAt: usage.lastSeen
            )
        }
    }

    // MARK: - Batching

    /// Splits events into request envelopes of <= 500 (server cap).
    static func chunked(_ events: [AtlasPromptEvent]) -> [AtlasPromptEventBatch] {
        stride(from: 0, to: events.count, by: maxBatchSize).map { start in
            AtlasPromptEventBatch(
                events: Array(events[start..<min(start + maxBatchSize, events.count)])
            )
        }
    }

    // MARK: - Helpers

    /// Lowercases and validates a SHA-256 hex hash; nil when malformed so
    /// the server doesn't skip the whole row.
    static func normalizedHash(_ hash: String) -> String? {
        let lowered = hash.lowercased()
        return lowered.range(of: hashPattern, options: .regularExpression) != nil ? lowered : nil
    }
}
