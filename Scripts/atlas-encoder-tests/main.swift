import Foundation

// Standalone assert harness for the atlas prompt-telemetry pure layer.
// Run via Scripts/atlas-encoder-tests.sh — see that script's header for why
// this exists instead of XCTest.

var failures = 0
func expect(_ condition: Bool, _ label: String) {
    if condition { print("PASS \(label)") } else { failures += 1; print("FAIL \(label)") }
}

func encodeToJSONString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value) else { return "<encode error>" }
    return String(data: data, encoding: .utf8) ?? "<utf8 error>"
}

// MARK: - Wire shape

let wireEvent = AtlasPromptEvent(
    source: "macos_widget",
    eventKind: "violation",
    appId: "chatgpt",
    promptHash: String(repeating: "ab", count: 32),
    action: "blocked",
    severity: "high",
    piiCategories: ["pii-email": 1],
    userExternalId: "auth0|abc123",
    sessionId: nil,
    occurrences: 1,
    occurredAt: "2026-06-12T10:00:00Z"
)
let wireJSON = encodeToJSONString(AtlasPromptEventBatch(events: [wireEvent]))
expect(wireJSON.contains("\"events\""), "batch envelope key is 'events'")
for key in ["\"source\":\"macos_widget\"", "\"event_kind\":\"violation\"", "\"app_id\":\"chatgpt\"",
            "\"prompt_hash\"", "\"action\":\"blocked\"", "\"severity\":\"high\"",
            "\"pii_categories\"", "\"user_external_id\"", "\"occurrences\":1", "\"occurred_at\""] {
    expect(wireJSON.contains(key), "wire JSON contains \(key)")
}
expect(!wireJSON.contains("session_id"), "nil optionals are omitted (extra=forbid-safe)")
expect(!wireJSON.contains("appVersion"), "no appVersion leaks into atlas payload")

// MARK: - UsageEvent rollup mapping

let rollup = UsageEvent(
    day: "2026-06-12", auth0Sub: "auth0|abc", promptlyAppId: "chatgpt",
    promptCount: 7, blockedCount: 2, redactedCount: 1, flaggedCount: 0,
    firstSeen: "2026-06-12T09:00:00Z", lastSeen: "2026-06-12T17:30:00Z"
)
let rollupEvents = AtlasPromptEventEncoder.events(from: rollup)
expect(rollupEvents.count == 3, "zero counters produce no events (7/2/1/0 -> 3 events)")
func find(_ events: [AtlasPromptEvent], action: String) -> AtlasPromptEvent? {
    events.first { $0.action == action }
}
let allowed = find(rollupEvents, action: "allowed")
expect(allowed?.eventKind == "activity", "promptCount -> activity/allowed")
expect(allowed?.occurrences == 7, "promptCount -> occurrences")
let redacted = find(rollupEvents, action: "redacted")
expect(redacted?.eventKind == "activity", "redactedCount -> activity/redacted (resolved activity)")
expect(redacted?.occurrences == 1, "redactedCount -> occurrences")
let blocked = find(rollupEvents, action: "blocked")
expect(blocked?.eventKind == "violation", "blockedCount -> violation/blocked")
expect(blocked?.occurrences == 2, "blockedCount -> occurrences")
expect(find(rollupEvents, action: "flagged") == nil, "flaggedCount 0 -> no flagged event")
expect(rollupEvents.allSatisfy { $0.source == "macos_widget" }, "source is macos_widget")
expect(rollupEvents.allSatisfy { $0.appId == "chatgpt" }, "app_id from promptlyAppId")
expect(rollupEvents.allSatisfy { $0.userExternalId == "auth0|abc" }, "user_external_id from auth0Sub")
expect(rollupEvents.allSatisfy { $0.occurredAt == "2026-06-12T17:30:00Z" }, "occurred_at = lastSeen")
let noExtras = rollupEvents.allSatisfy { $0.promptHash == nil && $0.severity == nil && $0.piiCategories == nil }
expect(noExtras, "rollups carry no hash/severity/categories")

let flaggedRollup = UsageEvent(
    day: "2026-06-12", auth0Sub: nil, promptlyAppId: "claude",
    promptCount: 0, blockedCount: 0, redactedCount: 0, flaggedCount: 20_001,
    firstSeen: "x", lastSeen: "y"
)
let flaggedEvents = AtlasPromptEventEncoder.events(from: flaggedRollup)
expect(flaggedEvents.count == 1 && flaggedEvents[0].eventKind == "violation"
       && flaggedEvents[0].action == "flagged", "flaggedCount -> violation/flagged")
expect(flaggedEvents[0].occurrences == 10_000, "occurrences clamped to server max 10000")
expect(flaggedEvents[0].userExternalId == nil, "nil auth0Sub -> nil user_external_id")

// MARK: - Batch chunking (server cap: 500 events/request)

let many = Array(repeating: wireEvent, count: 1101)
let chunks = AtlasPromptEventEncoder.chunked(many)
expect(chunks.count == 3, "1101 events -> 3 chunks")
expect(chunks[0].events.count == 500 && chunks[1].events.count == 500 && chunks[2].events.count == 101,
       "chunks are 500/500/101")
expect(AtlasPromptEventEncoder.chunked([]).isEmpty, "empty input -> no chunks")

// MARK: - PolicyViolation mapping

func makeViolation(action: ActionType, hash: String = String(repeating: "0a", count: 32),
                   matched: String? = nil, output: String = "Detected EMAIL") -> PolicyViolation {
    PolicyViolation(
        id: "v-1", policyInstanceId: "pi-1", applicationId: "notion",
        timestamp: "2026-06-12T11:22:33Z", actionTaken: action, severity: .critical,
        detectorId: "pii-detector", promptHash: hash, user: "auth0|xyz",
        evidence: PolicyViolationEvidence(
            detectorOutput: output, matchedPattern: matched, confidence: 0.9, urlHost: "notion.so"),
        reviewed: false
    )
}

let blockedViolation = AtlasPromptEventEncoder.event(from: makeViolation(action: .block))
expect(blockedViolation?.eventKind == "violation", "violation -> event_kind violation")
expect(blockedViolation?.action == "blocked", "ActionType.block -> blocked")
expect(blockedViolation?.severity == "critical", "PolicySeverity 1:1")
expect(blockedViolation?.appId == "notion", "app_id from applicationId")
expect(blockedViolation?.promptHash == String(repeating: "0a", count: 32), "valid hash forwarded")
expect(blockedViolation?.piiCategories == ["pii-detector": 1], "detectorId -> pii_categories count 1")
expect(blockedViolation?.userExternalId == "auth0|xyz", "user -> user_external_id")
expect(blockedViolation?.occurredAt == "2026-06-12T11:22:33Z", "occurred_at = timestamp")
expect(blockedViolation?.occurrences == 1, "violations are single occurrences")

expect(AtlasPromptEventEncoder.event(from: makeViolation(action: .flag))?.action == "flagged", "flag -> flagged")
expect(AtlasPromptEventEncoder.event(from: makeViolation(action: .log))?.action == "logged", "log -> logged")
expect(AtlasPromptEventEncoder.event(from: makeViolation(action: .redact))?.action == "redacted", "redact -> redacted")
for other in [ActionType.rewrite, .notify, .requireReview] {
    let mapped = AtlasPromptEventEncoder.event(from: makeViolation(action: other))
    expect(mapped != nil && mapped?.action == nil, "\(other.rawValue) -> violation event with nil action")
}
expect(AtlasPromptEventEncoder.event(from: makeViolation(action: .evaluated)) == nil,
       "evaluated ticks are dropped (clean prompts counted via rollups)")

// Hash hygiene
expect(AtlasPromptEventEncoder.event(from: makeViolation(action: .block,
       hash: String(repeating: "0A", count: 32)))?.promptHash == String(repeating: "0a", count: 32),
       "uppercase hash is lowercased")
expect(AtlasPromptEventEncoder.event(from: makeViolation(action: .block, hash: "not-a-hash"))?.promptHash == nil,
       "malformed hash dropped to nil, event kept")

// MARK: - PRIVACY: no content fragment ever reaches the wire

let sentinel = "SENTINEL-RAW-PROMPT-FRAGMENT-123-45-6789"
let leaky = makeViolation(action: .block, matched: sentinel, output: "matched: \(sentinel)")
if let event = AtlasPromptEventEncoder.event(from: leaky) {
    let json = encodeToJSONString(AtlasPromptEventBatch(events: [event]))
    expect(!json.contains(sentinel), "evidence.matchedPattern/detectorOutput never reach atlas JSON")
    expect(!json.contains("matchedPattern") && !json.contains("detectorOutput") && !json.contains("evidence"),
           "no evidence-shaped keys in atlas JSON")
} else {
    expect(false, "blocked violation must produce an event")
}

if failures > 0 { print("\(failures) FAILURES"); exit(1) }
print("ALL TESTS PASSED")
