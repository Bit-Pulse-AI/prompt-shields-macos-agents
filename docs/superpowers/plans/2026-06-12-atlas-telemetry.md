# Atlas Prompt Telemetry Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send the macOS widget's existing prompt telemetry (daily UsageEvent rollups + PolicyViolations) to atlas.ai's `POST /api/v1/telemetry/prompt-events` endpoint, hash + metadata only, gated off unless an atlas URL and API key are configured.

**Architecture:** A new pure `AtlasPromptEventEncoder` translates the existing `UsageEvent` / `PolicyViolation` types into atlas wire events (`AtlasPromptEvent`). A new minimal `AtlasPromptEventTransport` (X-API-Key auth, separate from the existing bearer-token `TelemetryTransport`) posts batches; `TelemetryClient` owns it as a second, independently-gated stream. Hooks: `UsageEventAggregator.flush()` (rollups) and `PolicyClient.reportViolation()` (violations). Everything fails open; existing AI-SPM telemetry is untouched.

**Tech Stack:** Swift 6.1 (Foundation-only for encoder + wire types), URLSession, macOS Keychain (existing `KeychainManagerImpl`), UserDefaults config key, standalone `swiftc` assert-harness for tests (see Ground truth — XCTest is not runnable headless in this repo).

**Tracking:** Linear PRO-16.

**Spec:** `atlas.ai/docs/superpowers/specs/2026-06-11-prompt-telemetry-design.md` (macOS widget client section). Wire contract as built: `atlas.ai/.worktrees/feat-prompt-telemetry/backend/app/schemas/telemetry.py` + `routers/telemetry.py`.

---

## Ground truth (verified 2026-06-12 on this machine)

**Wire contract (read from the built backend, not just the spec):**
- `POST {base}/api/v1/telemetry/prompt-events`, header `X-API-Key` (router prefix `/telemetry`, mounted under `/api/v1`; auth via `require_api_key`, same model as the extension heartbeat endpoint).
- Body `{"events": [...]}`, 1–500 events per request.
- Per-event fields (Pydantic `extra="forbid"` — any unknown key rejects that row; **do not send `appVersion` or anything extra**): `source`, `event_kind` (required); `app_id` ≤120, `prompt_hash` (exactly 64 lowercase hex when present — validator lowercases, then hard-rejects the row on mismatch), `action` ∈ `allowed|logged|redacted|flagged|blocked`, `severity` ∈ `low|medium|high|critical`, `pii_categories` dict str→int (counts ≥1, keys ≤100 chars), `device_fingerprint` ≤100, `user_external_id` ≤255, `session_id` ≤120, `occurrences` 1–10000 (default 1), `occurred_at` ISO-8601 (server-now when omitted). `vendor`/`model`/`tokens_*`/`estimated_cost_usd` are SDK-only — never send from macOS.
- Response `{ingested, skipped, skipped_reasons}`; invalid rows are skipped individually, the batch still succeeds.

**macOS types (read from source):**
- `UsageEvent` (`Managers/Telemetry/TelemetryTypes.swift:54`): `day`, `auth0Sub?`, `promptlyAppId`, `promptCount`, `blockedCount`, `redactedCount`, `flaggedCount`, `firstSeen`/`lastSeen` (ISO strings). Produced by `UsageEventAggregator.flush()` (`Managers/Telemetry/UsageEventAggregator.swift:109`). No prompt text anywhere in this type.
- `PolicyViolation` (`Managers/Policy/PolicyTypes.swift:175`): `id`, `policyInstanceId`, `applicationId`, `timestamp` (ISO), `actionTaken: ActionType`, `severity: PolicySeverity`, `detectorId`, `promptHash` (SHA-256 hex), `user?`, `evidence: PolicyViolationEvidence`, `reviewed`.
- **PRIVACY — confirmed content-fragment fields:** `PolicyViolationEvidence` (`PolicyTypes.swift:190`) carries `detectorOutput: String` and `matchedPattern: String?` — `matchedPattern` is the matched prompt substring (capped at 200 chars, set from `TriggeredPolicy.matchedSubstring` in `PolicyEnforcer.makeViolation`). **The encoder must never read `evidence`.** This is an explicit encoder property with a sentinel test (Task 3).
- `ActionType` (`PolicyTypes.swift:65`): `block, flag, log, redact, rewrite, notify, requireReview ("require_review"), evaluated`. `evaluated` is a synthetic per-clean-prompt tick (`PolicyEnforcer.makeEvaluatedTick`, instance id `"evaluation-only"`) emitted on every `.allow` decision — it is NOT a violation.
- `PolicySeverity` (`PolicyTypes.swift:28`): `low, medium, high, critical` — 1:1 with the atlas enum.
- Violation chokepoint: every violation (including evaluated ticks) flows through `PolicyClient.reportViolation` (`Managers/Policy/PolicyClient.swift:108`); callers are `ActionView.swift:584` and the evaluated tick at `ActionView.swift:624→584`.
- `app_id`: `promptlyAppId` / `applicationId` already carry monitored-app registry ids (`chatgpt`, `claude`, …) or `shadow-<bundleId>` (`ActionView.swift:609-618`).
- Auth0 sub: available as `credentials.id` in `AuthManager.swift:185` (used for `PersonSyncRequest.auth0Sub`). Note: `ActionView.swift:622` currently records usage with `auth0Sub: nil`, so rollup events will often have `user_external_id` nil — that's pre-existing, not this plan's problem.

**Transport + config (read from source):**
- `HTTPTelemetryTransport` (`Managers/Telemetry/TelemetryClient.swift:113`): `baseURL` + optional `bearerTokenProvider` → `Authorization: Bearer`. **Wrong auth mechanism for atlas** — and the existing `TelemetryTransport` protocol's 4 endpoints all target the AI-SPM dashboard. We add a separate minimal transport rather than overloading it.
- Config gating precedent: `MainApp.configurePolicyClient()` (`MainApp.swift:184-218`) reads UserDefaults key `ai.bit-pulse.promptshields.aiSPMDashboardURL`; empty → `NullPolicyTransport` + `NullTelemetryTransport`, zero behavior change.
- **Config decision (deviation from spec wording, grounded in code):** the spec says to reuse `aiSPMDashboardURL`, but that key drives `HTTPPolicyTransport` → `GET {url}/api/policies` on the Next.js AI-SPM dashboard. atlas.ai is a different deployment with a different API surface; reusing the key would point the policy fetch at atlas. So: **new UserDefaults key `ai.bit-pulse.promptshields.atlasTelemetryURL`** for the base URL, **API key in the Keychain** via the existing `KeychainManagerImpl` (new `KeychainManagerKey` case), per the spec's Keychain requirement. Stream is active only when the URL parses AND the key loads; otherwise `NullAtlasPromptEventTransport`.
- Keychain: `KeychainManagerImpl` (`Managers/Keychain/KeychainManager.swift`) stores items by `KeychainManagerKey` enum case via private `saveSecureData`/`loadSecureData`/`deleteSecureData`; extend with an `atlasTelemetryAPIKey` case + string accessors.

**Test tooling reality (the key risk — all verified by running commands):**
- `xcode-select` points at CommandLineTools; `xcodebuild` only works with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` prefixed (verified: `-list` resolves packages and prints targets/schemes).
- **Headless XCTest is broken in this repo.** Verified failures:
  - `xcodebuild test -scheme PromptShields.MacOS.Widget-Dev …` → "Tests in the target 'PromptShields.MacOS.WidgetTests' can't be run because 'PromptShields.MacOS.WidgetTests' isn't a member of the specified test plan or scheme."
  - `xcodebuild test -scheme PromptShields.MacOS.Widget-Prod …` → "Scheme … is not currently configured for the test action."
  - There are **no shared `.xcscheme` files at all** (schemes are auto-generated from targets, no Test action), and the test target's `TEST_HOST` in `project.pbxproj` points at `PromptShields.MacOS.Widget.app` while the app targets' `PRODUCT_NAME = "Promptly"` (product is `Promptly.app`) — the host-app reference is stale. The existing `PromptShields.MacOS.WidgetTests/*.swift` files are not runnable from the CLI as configured. Fixing the project's test config is out of scope for PRO-16 (flagged separately).
- **Verification harness mechanism — PROVEN working:** `swiftc` 6.1.2 compiles `PolicyTypes.swift` + `TelemetryTypes.swift` standalone together with a `main.swift` containing top-level asserts, and the binary runs (probe printed `PROBE OK`). Both files import only Foundation. Therefore: the new encoder + wire-type files MUST stay Foundation-only (no AppKit, no `@MainActor`, no singletons) so the harness can compile them — the harness compile itself enforces this purity. Top-level executable code requires the file to be named `main.swift`.
- **Full-app compile gate — PROVEN working (exit 0, BUILD SUCCEEDED):** `DEVELOPER_DIR=… xcodebuild build -scheme PromptShields.MacOS.Widget-Dev -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO` (DerivedData cache exists from prior IDE builds; `CODE_SIGNING_ALLOWED=NO` avoids signing variance for a compile check). First clean run takes several minutes.

**Mapping decisions (locked here so the encoder is unambiguous):**

| Input | atlas event(s) |
|---|---|
| `UsageEvent.promptCount > 0` | `event_kind: activity`, `action: allowed`, `occurrences = min(promptCount, 10000)` |
| `UsageEvent.redactedCount > 0` | `event_kind: activity`, `action: redacted`, occurrences likewise |
| `UsageEvent.flaggedCount > 0` | `event_kind: violation`, `action: flagged`, occurrences likewise |
| `UsageEvent.blockedCount > 0` | `event_kind: violation`, `action: blocked`, occurrences likewise |
| (all rollup events) | `app_id = promptlyAppId`, `user_external_id = auth0Sub`, `occurred_at = lastSeen`, no hash/severity/categories |
| `PolicyViolation` (actionTaken ≠ `.evaluated`) | `event_kind: violation`, `action`: block→blocked, flag→flagged, log→logged, redact→redacted, rewrite/notify/requireReview→nil; `severity` 1:1; `prompt_hash` = lowercased `promptHash` if it matches `^[0-9a-f]{64}$`, else nil (a bad hash would skip the whole row server-side — better to keep the event and drop the hash); `pii_categories = [detectorId: 1]` (detectors short-circuit at first match, so count is 1); `app_id = applicationId`, `user_external_id = user`, `occurred_at = timestamp`, `occurrences = 1` |
| `PolicyViolation` with `actionTaken == .evaluated` | **dropped (encoder returns nil)** — deliberate refinement of the spec's "map to null action": an evaluated tick is a clean-prompt denominator already counted as `promptCount → activity/allowed`; emitting it as a `violation` row would corrupt the dashboard's violation_rate and double-count |
| `evidence.*`, `policyInstanceId`, `id`, `reviewed` | **never read** (privacy + irrelevant) |
| `session_id`, `device_fingerprint` | not sent from macOS (nil, omitted from JSON) — nothing in the app produces them today; the wire struct has `session_id` for future use |

JSONEncoder omits nil optionals (synthesized `encodeIfPresent`), which is exactly what `extra="forbid"` + nullable columns want.

## File structure

- **Create** `PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventTypes.swift` — wire structs (`AtlasPromptEvent`, `AtlasPromptEventBatch`) with snake_case CodingKeys. Foundation-only.
- **Create** `PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventEncoder.swift` — pure mapping functions + batch chunking helper. Foundation-only, stateless enum.
- **Create** `Scripts/atlas-encoder-tests/main.swift` — assert-based verification harness (the "test suite" for the pure layer).
- **Create** `Scripts/atlas-encoder-tests.sh` — compile-and-run wrapper so the harness is one command.
- **Modify** `PromptShields.MacOS.Widget/Managers/Telemetry/TelemetryClient.swift` — add `AtlasPromptEventTransport` protocol + `HTTPAtlasPromptEventTransport` (X-API-Key) + `NullAtlasPromptEventTransport`; `TelemetryClient` gains the atlas stream (`setAtlasTransport`, `flushAtlasPromptEvents`, `reportAtlasViolation`).
- **Modify** `PromptShields.MacOS.Widget/Managers/Telemetry/UsageEventAggregator.swift:109-138` — `flush()` also encodes + flushes atlas events.
- **Modify** `PromptShields.MacOS.Widget/Managers/Policy/PolicyClient.swift:108-114` — `reportViolation` also forwards to the atlas stream.
- **Modify** `PromptShields.MacOS.Widget/Managers/Keychain/KeychainManager.swift` — `atlasTelemetryAPIKey` key case + save/load/delete string accessors.
- **Modify** `PromptShields.MacOS.Widget/MainApp.swift:184-218` — wire the atlas transport when URL + key are configured.

All shell commands below run from the repo root: `/Users/junseki/Documents/GitHub/prompt-shields-macos-widget`.

---

### Task 1: Wire types + verification harness skeleton

**Files:**
- Create: `PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventTypes.swift`
- Create: `Scripts/atlas-encoder-tests/main.swift`
- Create: `Scripts/atlas-encoder-tests.sh`

- [ ] **Step 1: Write the harness runner script**

`Scripts/atlas-encoder-tests.sh` (then `chmod +x Scripts/atlas-encoder-tests.sh`):

```bash
#!/usr/bin/env bash
# atlas-encoder-tests.sh — compiles the pure atlas-telemetry layer with a
# standalone assert harness and runs it. This is the CLI test path for
# AtlasPromptEventEncoder because the Xcode project's XCTest target is not
# runnable headless (no Test action in any scheme; stale TEST_HOST).
# The harness compile also enforces that the encoder stays Foundation-only.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)/atlas-encoder-tests"
swiftc -o "$OUT" \
  PromptShields.MacOS.Widget/Managers/Policy/PolicyTypes.swift \
  PromptShields.MacOS.Widget/Managers/Telemetry/TelemetryTypes.swift \
  PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventTypes.swift \
  PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventEncoder.swift \
  Scripts/atlas-encoder-tests/main.swift
"$OUT"
```

- [ ] **Step 2: Write the failing harness (JSON wire-shape assertions)**

`Scripts/atlas-encoder-tests/main.swift` (top-level code is legal only in a file named `main.swift` — verified):

```swift
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
```

- [ ] **Step 3: Run harness to verify it fails**

Run: `./Scripts/atlas-encoder-tests.sh`
Expected: FAIL — compile error `cannot find 'AtlasPromptEvent' in scope` (and missing file error for `AtlasPromptEventEncoder.swift`; create it as an empty placeholder containing only `import Foundation` so the compile failure is the missing types, not the missing file).

- [ ] **Step 4: Implement the wire types**

`PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventTypes.swift`:

```swift
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
```

Also create the placeholder `PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventEncoder.swift` containing just `import Foundation` (filled in by Task 2).

- [ ] **Step 5: Run harness to verify it passes**

Run: `./Scripts/atlas-encoder-tests.sh`
Expected: every `PASS` line, then `ALL TESTS PASSED`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventTypes.swift \
        PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventEncoder.swift \
        Scripts/atlas-encoder-tests
git commit -m "feat(telemetry): atlas prompt-event wire types + CLI test harness (PRO-16)"
```

Note: the two new `.swift` files land in the app automatically — the Xcode project uses `fileSystemSynchronizedGroups`, so files added under `PromptShields.MacOS.Widget/` join the targets without editing `project.pbxproj`.

---

### Task 2: Encoder — UsageEvent rollups → activity/violation events

**Files:**
- Modify: `PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventEncoder.swift`
- Modify: `Scripts/atlas-encoder-tests/main.swift`

- [ ] **Step 1: Add failing asserts to the harness** (before the `if failures > 0` footer)

```swift
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
expect(rollupEvents.allSatisfy { $0.promptHash == nil && $0.severity == nil && $0.piiCategories == nil },
       "rollups carry no hash/severity/categories")

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
```

- [ ] **Step 2: Run harness to verify it fails**

Run: `./Scripts/atlas-encoder-tests.sh`
Expected: FAIL — compile error `enum 'AtlasPromptEventEncoder' has no member 'events'` (or `cannot find 'AtlasPromptEventEncoder'`).

- [ ] **Step 3: Implement the encoder (rollup half + chunking)**

Replace `AtlasPromptEventEncoder.swift` content:

```swift
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
```

- [ ] **Step 4: Run harness to verify it passes**

Run: `./Scripts/atlas-encoder-tests.sh`
Expected: `ALL TESTS PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventEncoder.swift Scripts/atlas-encoder-tests/main.swift
git commit -m "feat(telemetry): encode UsageEvent rollups as atlas prompt events (PRO-16)"
```

---

### Task 3: Encoder — PolicyViolation → violation events (with privacy sentinel test)

**Files:**
- Modify: `PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventEncoder.swift`
- Modify: `Scripts/atlas-encoder-tests/main.swift`

- [ ] **Step 1: Add failing asserts to the harness**

```swift
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
```

- [ ] **Step 2: Run harness to verify it fails**

Run: `./Scripts/atlas-encoder-tests.sh`
Expected: FAIL — compile error `has no member 'event(from:)'`.

- [ ] **Step 3: Implement the violation half**

Add to `AtlasPromptEventEncoder`:

```swift
    // MARK: - PolicyViolation

    /// Maps one PolicyViolation post to a violation wire event.
    /// Returns nil for `.evaluated` ticks (see header comment).
    /// PRIVACY: reads only id-free metadata — never `violation.evidence`.
    static func event(from violation: PolicyViolation) -> AtlasPromptEvent? {
        guard let action = mapAction(violation.actionTaken) else { return nil }
        return AtlasPromptEvent(
            source: source,
            eventKind: "violation",
            appId: violation.applicationId,
            promptHash: normalizedHash(violation.promptHash),
            action: action.wireValue,
            severity: violation.severity.rawValue,
            piiCategories: [violation.detectorId: 1],
            userExternalId: violation.user,
            sessionId: nil,
            occurrences: 1,
            occurredAt: violation.timestamp
        )
    }

    /// Wire action mapping. `.some(.none)` = emit the event with a null
    /// action (real policy hits with non-wire actions); `nil` = drop.
    private enum MappedAction {
        case named(String)
        case none
        var wireValue: String? {
            if case .named(let value) = self { return value }
            return nil
        }
    }

    private static func mapAction(_ action: ActionType) -> MappedAction? {
        switch action {
        case .block: return .named("blocked")
        case .flag: return .named("flagged")
        case .log: return .named("logged")
        case .redact: return .named("redacted")
        case .rewrite, .notify, .requireReview: return MappedAction.none
        case .evaluated: return nil  // denominator tick, not a violation
        }
    }
```

- [ ] **Step 4: Run harness to verify it passes**

Run: `./Scripts/atlas-encoder-tests.sh`
Expected: `ALL TESTS PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventEncoder.swift Scripts/atlas-encoder-tests/main.swift
git commit -m "feat(telemetry): encode PolicyViolations as atlas events, evidence never read (PRO-16)"
```

---

### Task 4: Atlas transport + TelemetryClient stream

No CLI-testable pure logic here (URLSession + @MainActor singleton); correctness gate is the harness staying green (Foundation-only purity of the files it compiles) plus the full-project compile in Task 6. Keep transport code symmetrical with `HTTPTelemetryTransport` directly above it.

**Files:**
- Modify: `PromptShields.MacOS.Widget/Managers/Telemetry/TelemetryClient.swift`

- [ ] **Step 1: Add the transport protocol + implementations** (bottom of `TelemetryClient.swift`, after `NullTelemetryTransport`)

```swift
// MARK: - Atlas prompt-event transport
//
// Separate from TelemetryTransport on purpose: the AI-SPM dashboard stream
// authenticates with a bearer token against a Next.js app, while atlas.ai
// wants an X-API-Key header against /api/v1/telemetry/prompt-events. The
// two are configured and gated independently.

protocol AtlasPromptEventTransport: Sendable {
    func reportPromptEvents(_ batch: AtlasPromptEventBatch) async throws
}

struct HTTPAtlasPromptEventTransport: AtlasPromptEventTransport {
    let baseURL: URL
    /// Loaded per-request (Keychain read) so a key pasted in Settings
    /// takes effect without restarting the stream.
    let apiKeyProvider: @Sendable () async -> String?

    private static let encoder = JSONEncoder()

    func reportPromptEvents(_ batch: AtlasPromptEventBatch) async throws {
        guard let apiKey = await apiKeyProvider(), !apiKey.isEmpty else {
            throw TelemetryTransportError.unconfigured
        }
        let url = baseURL.appendingPathComponent("api/v1/telemetry/prompt-events")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 10
        request.httpBody = try Self.encoder.encode(batch)

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

struct NullAtlasPromptEventTransport: AtlasPromptEventTransport {
    func reportPromptEvents(_ batch: AtlasPromptEventBatch) async throws {}
}
```

- [ ] **Step 2: Add the atlas stream to `TelemetryClient`** (inside the class, after the tour-engagement section)

```swift
    // MARK: - Atlas prompt events (batched, fail-open)

    private var atlasTransport: AtlasPromptEventTransport = NullAtlasPromptEventTransport()

    /// Wired by MainApp.configurePolicyClient at boot. Stays the Null
    /// transport unless an atlas URL is configured — zero behaviour
    /// change for tenants without atlas telemetry.
    func setAtlasTransport(_ transport: AtlasPromptEventTransport) {
        self.atlasTransport = transport
    }

    /// Posts encoded prompt events in <=500-event chunks. Fail-open like
    /// every other stream here: errors log and drop.
    func flushAtlasPromptEvents(_ events: [AtlasPromptEvent]) async {
        guard !events.isEmpty else { return }
        for batch in AtlasPromptEventEncoder.chunked(events) {
            do {
                try await atlasTransport.reportPromptEvents(batch)
                logger.debug("flushed \(batch.events.count) atlas prompt events")
            } catch {
                logger.debug("atlas prompt-event batch failed: \(error.localizedDescription)")
            }
        }
    }

    /// Encodes and posts a single PolicyViolation (evaluated ticks encode
    /// to nil and are skipped — see AtlasPromptEventEncoder).
    func reportAtlasViolation(_ violation: PolicyViolation) async {
        guard let event = AtlasPromptEventEncoder.event(from: violation) else { return }
        await flushAtlasPromptEvents([event])
    }
```

- [ ] **Step 3: Update the file header comment** — extend the endpoint list at the top of `TelemetryClient.swift` with `//   - POST {atlas}/api/v1/telemetry/prompt-events  (AtlasPromptEventBatch, X-API-Key)` and a line noting the atlas stream is gated by `atlasTelemetryURL` + Keychain key, independent of `aiSPMDashboardURL`.

- [ ] **Step 4: Verify the harness still passes (purity check)**

Run: `./Scripts/atlas-encoder-tests.sh`
Expected: `ALL TESTS PASSED` (the harness does not compile `TelemetryClient.swift`; this confirms the pure layer wasn't polluted).

- [ ] **Step 5: Commit**

```bash
git add PromptShields.MacOS.Widget/Managers/Telemetry/TelemetryClient.swift
git commit -m "feat(telemetry): X-API-Key atlas transport + prompt-event stream in TelemetryClient (PRO-16)"
```

---

### Task 5: Keychain key storage + config gating + pipeline hooks

**Files:**
- Modify: `PromptShields.MacOS.Widget/Managers/Keychain/KeychainManager.swift`
- Modify: `PromptShields.MacOS.Widget/MainApp.swift:184-218`
- Modify: `PromptShields.MacOS.Widget/Managers/Telemetry/UsageEventAggregator.swift:109-138`
- Modify: `PromptShields.MacOS.Widget/Managers/Policy/PolicyClient.swift:108-114`

- [ ] **Step 1: Keychain accessors.** In `KeychainManager.swift`:

Add the enum case:

```swift
enum KeychainManagerKey: String, Sendable {
    case userCredentials = "App credentials"
    case encryptionToken = "Internal Token"
    case atlasTelemetryAPIKey = "Atlas Telemetry API Key"
}
```

Add to the `KeychainManager` protocol:

```swift
    /// Saves the atlas.ai telemetry API key (aigrc_*) to the keychain.
    func saveAtlasTelemetryAPIKey(_ key: String) throws

    /// Loads the atlas.ai telemetry API key, or throws .itemNotFound.
    func loadAtlasTelemetryAPIKey() throws -> String

    /// Deletes the atlas.ai telemetry API key from the keychain.
    func deleteAtlasTelemetryAPIKey() throws
```

Add to `KeychainManagerImpl` (next to the encryption-key section, reusing the private `saveSecureData`/`loadSecureData`/`deleteSecureData` helpers):

```swift
    // MARK: - Atlas Telemetry API Key

    func saveAtlasTelemetryAPIKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.dataEncodingError
        }
        try saveSecureData(key: .atlasTelemetryAPIKey, secureData: data, override: true)
    }

    func loadAtlasTelemetryAPIKey() throws -> String {
        let data = try loadSecureData(key: .atlasTelemetryAPIKey)
        guard let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataDecodingError
        }
        return key
    }

    func deleteAtlasTelemetryAPIKey() throws {
        try deleteSecureData(key: .atlasTelemetryAPIKey)
    }
```

- [ ] **Step 2: MainApp wiring.** In `configurePolicyClient()` (`MainApp.swift`), after `TelemetryClient.shared.setTransport(telemetryTransport)` and before `UsageEventAggregator.shared.start()`:

```swift
        // Atlas prompt-telemetry stream (atlas.ai grc.prompt_events).
        // Gated independently of the AI-SPM dashboard: active only when an
        // atlas URL is set AND an API key exists in the Keychain. Absent
        // either, the Null transport keeps behaviour identical to today.
        // QA: defaults write <bundle-id> ai.bit-pulse.promptshields.atlasTelemetryURL <url>
        let atlasURLString = UserDefaults.standard.string(
            forKey: "ai.bit-pulse.promptshields.atlasTelemetryURL"
        ) ?? ""
        if !atlasURLString.isEmpty, let atlasURL = URL(string: atlasURLString) {
            TelemetryClient.shared.setAtlasTransport(HTTPAtlasPromptEventTransport(
                baseURL: atlasURL,
                apiKeyProvider: { try? KeychainManagerImpl.shared.loadAtlasTelemetryAPIKey() }
            ))
        }
```

(No `else` needed — `TelemetryClient` defaults to `NullAtlasPromptEventTransport`. A configured URL with a missing key also stays inert: the transport throws `.unconfigured`, which the client logs and drops.)

- [ ] **Step 3: Rollup hook.** In `UsageEventAggregator.flush()` (`UsageEventAggregator.swift`), after the existing `flushUsageBatch` call:

```swift
        // Mirror the rollups onto the atlas prompt-event stream (noop
        // unless MainApp wired an atlas transport).
        await TelemetryClient.shared.flushAtlasPromptEvents(
            events.flatMap(AtlasPromptEventEncoder.events(from:))
        )
```

- [ ] **Step 4: Violation hook.** In `PolicyClient.reportViolation` (`PolicyClient.swift`) — this is the single chokepoint for both real violations (`ActionView.swift:584`) and evaluated ticks (which the encoder drops):

```swift
    func reportViolation(_ violation: PolicyViolation) async {
        do {
            try await transport.reportViolation(violation)
        } catch {
            logger.error("Violation report failed: \(error.localizedDescription)")
        }
        // Also mirror onto the atlas prompt-event stream (hash + metadata
        // only — the encoder never reads `evidence`). Independent of the
        // dashboard post above: each fails open on its own.
        await TelemetryClient.shared.reportAtlasViolation(violation)
    }
```

- [ ] **Step 5: Verify harness still green, then commit**

Run: `./Scripts/atlas-encoder-tests.sh`
Expected: `ALL TESTS PASSED`

```bash
git add PromptShields.MacOS.Widget/Managers/Keychain/KeychainManager.swift \
        PromptShields.MacOS.Widget/MainApp.swift \
        PromptShields.MacOS.Widget/Managers/Telemetry/UsageEventAggregator.swift \
        PromptShields.MacOS.Widget/Managers/Policy/PolicyClient.swift
git commit -m "feat(telemetry): gate + wire atlas prompt-event stream (UserDefaults URL, Keychain key) (PRO-16)"
```

---

### Task 6: Final verification

- [ ] **Step 1: Pure-layer tests**

Run: `./Scripts/atlas-encoder-tests.sh`
Expected: all `PASS` lines, `ALL TESTS PASSED`, exit 0.

- [ ] **Step 2: Full-project compile (proves the @MainActor/UI wiring builds)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project PromptShields.MacOS.Widget.xcodeproj \
  -scheme PromptShields.MacOS.Widget-Dev \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: `** BUILD SUCCEEDED **` (warnings tolerated, errors not). The `DEVELOPER_DIR` prefix is mandatory — bare `xcodebuild` fails on this machine (xcode-select points at CommandLineTools). Note `xcodebuild test` is NOT available (see Ground truth); do not "fix" a red build by deleting harness coverage.

- [ ] **Step 3: Privacy grep-gate (cheap structural check)**

```bash
grep -n "evidence" PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventEncoder.swift \
                   PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventTypes.swift | grep -v "^.*//" || echo "CLEAN"
```

Expected: `CLEAN` (the only `evidence` mentions in the atlas files are comments).

- [ ] **Step 4: Optional end-to-end smoke (needs the atlas backend running locally)**

From the atlas worktree, start the backend, mint an `aigrc_` API key for a test tenant, then:

```bash
defaults write ai.bit-pulse.PromptShields-MacOS-Widget-Dev ai.bit-pulse.promptshields.atlasTelemetryURL "http://localhost:8000"
# paste the API key into the Keychain (until a Settings UI exists):
#   security add-generic-password -s <keyChainManagerServiceName value> -a "Atlas Telemetry API Key" -w "aigrc_..."
```

Run the Dev app, trigger a suggestion in a monitored app, wait for/force a flush, and confirm rows in `grc.prompt_events` with `source = 'macos_widget'`. Document the result; skip if no local backend is available (the wire shape is already pinned by the harness against the schema).

- [ ] **Step 5: Final commit + report**

Commit anything outstanding, then summarize: tasks completed, harness output, build result, any deviations. Update Linear PRO-16.
