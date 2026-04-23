import Foundation
import ApplicationServices
import os

// Structured detection trace (PS-11). When enabled, every poll cycle
// emits a log line summarising what the pipeline found — so Henrik's
// "typed PII in ChatGPT, nothing happened" bug can be diagnosed
// without adding prints everywhere.
//
// Enable via:
//   defaults write ai.bit-pulse.PromptShields-MacOS-Widget-Dev \
//       ai.bit-pulse.promptshields.detectionTrace -bool YES
//   log stream --predicate 'subsystem == "ai.bit-pulse.PromptShields-MacOS-Widget-Dev" \
//       AND category == "Detection"' --level debug
//
// Release behaviour: trace is opt-in even in debug builds (no PII ever
// hits the log — we only emit role, bundleId, frame, and short status
// codes, never the text contents).

enum DetectionTrace {
    private static let userDefaultsKey = "ai.bit-pulse.promptshields.detectionTrace"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "Detection"
    )

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// Emit a key=value line. Called from hot-path code so we short-circuit
    /// when the trace is off to avoid building the string.
    static func log(
        _ event: String,
        bundleId: String? = nil,
        role: String? = nil,
        editable: Bool? = nil,
        textLen: Int? = nil,
        note: String? = nil
    ) {
        guard isEnabled else { return }
        var parts: [String] = ["event=\(event)"]
        if let bundleId { parts.append("bundle=\(bundleId)") }
        if let role { parts.append("role=\(role)") }
        if let editable { parts.append("editable=\(editable)") }
        if let textLen { parts.append("len=\(textLen)") }
        if let note { parts.append("note=\(note)") }
        logger.debug("\(parts.joined(separator: " "), privacy: .public)")
    }
}
