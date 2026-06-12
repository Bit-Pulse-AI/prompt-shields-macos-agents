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

if failures > 0 { print("\(failures) FAILURES"); exit(1) }
print("ALL TESTS PASSED")
