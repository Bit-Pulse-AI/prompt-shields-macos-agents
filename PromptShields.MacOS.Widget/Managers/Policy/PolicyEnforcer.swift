import Foundation
import CryptoKit
import os

// PolicyEnforcer — the on-device PEP. Given a prompt and the app it's
// being typed into, it runs every active PolicyInstance's detectors and
// returns a `PolicyDecision` summarising what should happen: redact (with
// the offending spans), block (with reason), flag (warn user), or log
// (silent telemetry).
//
// Design constraints:
//   - Must be cheap on the AXObserver hot path (every keystroke debounced
//     150ms). Detectors short-circuit at the first match; no LLM calls
//     happen here.
//   - Pure-functional: no side effects beyond emitting violations.
//     Network reporting is the caller's responsibility (PolicyEnforcer
//     just produces the violation records).
//   - Reuses the existing `PIIDetector` for `pii_detector` and
//     `secrets_scanner` detector types so we don't double-implement.
//
// Action precedence (matches the AI-SPM dashboard's enforcement_mode
// semantics): block > redact > flag > log. If multiple instances match
// the same prompt, the strongest action wins.

struct PolicyDecision: Sendable, Equatable {
    enum Action: Sendable, Equatable {
        case allow
        case log
        case flag
        case redact
        case block(reason: String)
    }

    let action: Action
    let triggered: [TriggeredPolicy]
    /// SHA-256 hex of the input. Computed once, reused if the caller
    /// emits violation records.
    let promptHash: String

    var requiresUserAttention: Bool {
        switch action {
        case .allow, .log: return false
        case .flag, .redact, .block: return true
        }
    }
}

struct TriggeredPolicy: Sendable, Equatable {
    let instance: PolicyInstance
    let detectorId: String
    let matchedSubstring: String?
    let confidence: Double
    let evidence: String
}

@MainActor
final class PolicyEnforcer {
    private let client: PolicyClient
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "PolicyEnforcer"
    )

    init(client: PolicyClient) {
        self.client = client
    }

    // MARK: - Public API

    /// Evaluate `text` against every policy that applies to `appId`.
    /// `stage` defaults to `.input` because Promptly intercepts pre-send.
    func evaluate(
        text: String,
        appId: String,
        stage: TriggerStage = .input
    ) -> PolicyDecision {
        let promptHash = Self.sha256Hex(text)
        guard !text.isEmpty else {
            return PolicyDecision(action: .allow, triggered: [], promptHash: promptHash)
        }

        var triggered: [TriggeredPolicy] = []
        var strongestAction: PolicyDecision.Action = .allow

        for instance in client.instances(forApp: appId) where instance.status == .active {
            guard let template = client.template(for: instance),
                  template.triggers.contains(where: { $0.stage == stage }) else {
                continue
            }

            for detector in template.detectors {
                guard let result = runDetector(detector, instance: instance, text: text) else { continue }
                triggered.append(TriggeredPolicy(
                    instance: instance,
                    detectorId: detector.id,
                    matchedSubstring: result.matchedSubstring,
                    confidence: result.confidence,
                    evidence: result.explanation
                ))

                let mapped = mapEnforcement(instance.enforcementMode, instance: instance)
                strongestAction = Self.stronger(strongestAction, mapped)
            }
        }

        return PolicyDecision(
            action: strongestAction,
            triggered: triggered,
            promptHash: promptHash
        )
    }

    /// Build a `PolicyViolation` from a triggered policy. The caller
    /// (ActionView / SuggestionDomainService) decides when/whether to
    /// post via `PolicyClient.reportViolation`.
    func makeViolation(
        from triggered: TriggeredPolicy,
        applicationId: String,
        promptHash: String,
        actionTaken: ActionType,
        user: String? = nil,
        urlHost: String? = nil
    ) -> PolicyViolation {
        PolicyViolation(
            id: UUID().uuidString,
            policyInstanceId: triggered.instance.id,
            applicationId: applicationId,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            actionTaken: actionTaken,
            severity: triggered.instance.severity,
            detectorId: triggered.detectorId,
            promptHash: promptHash,
            user: user,
            evidence: PolicyViolationEvidence(
                detectorOutput: triggered.evidence,
                matchedPattern: triggered.matchedSubstring,
                confidence: triggered.confidence,
                urlHost: urlHost
            ),
            reviewed: false
        )
    }

    /// Synthetic envelope emitted for *every* `.allow` decision so the
    /// dashboard knows how often the policy ran without firing. Not tied
    /// to a specific instance — uses a sentinel id "evaluation-only" the
    /// dashboard groups on. Promptly's UX never sees this; it exists
    /// purely to give SPM a denominator for FP rates.
    func makeEvaluatedTick(
        applicationId: String,
        promptHash: String,
        user: String? = nil,
        urlHost: String? = nil
    ) -> PolicyViolation {
        PolicyViolation(
            id: UUID().uuidString,
            policyInstanceId: "evaluation-only",
            applicationId: applicationId,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            actionTaken: .evaluated,
            severity: .low,
            detectorId: "promptly-pep",
            promptHash: promptHash,
            user: user,
            evidence: PolicyViolationEvidence(
                detectorOutput: "Evaluated, no policy match",
                matchedPattern: nil,
                confidence: 1.0,
                urlHost: urlHost
            ),
            reviewed: true
        )
    }

    // MARK: - Detector runners

    private struct DetectorMatch {
        let matchedSubstring: String?
        let confidence: Double
        let explanation: String
    }

    private func runDetector(
        _ detector: PolicyDetector,
        instance: PolicyInstance,
        text: String
    ) -> DetectorMatch? {
        switch detector.type {
        case .regex:
            return runRegex(text: text, config: instance.parameterValues[detector.configRef])
        case .keywordList:
            return runKeywords(text: text, config: instance.parameterValues[detector.configRef])
        case .piiDetector:
            return runPIIDetector(text: text)
        case .secretsScanner:
            return runSecretsScanner(text: text)
        case .entropy:
            return runEntropy(text: text)
        case .classifier:
            return runHeuristicClassifier(text: text, detectorId: detector.id, threshold: instance.parameterValues[detector.configRef]?.value.asDouble ?? 0.75)
        case .llmJudge, .rateCounter:
            // These need backend state — Promptly is a local PEP that defers
            // to the cloud judge / rate counter. Skip for now; the dashboard
            // stamps actionable rate-limit decisions on incoming traffic.
            return nil
        }
    }

    private func runRegex(text: String, config: PolicyAnyCodable?) -> DetectorMatch? {
        guard let patterns = config?.value.asStringArray else { return nil }
        for pattern in patterns where !pattern.isEmpty {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let r = Range(match.range, in: text) {
                return DetectorMatch(
                    matchedSubstring: String(text[r]),
                    confidence: 1.0,
                    explanation: "Matched regex \"\(pattern)\""
                )
            }
        }
        return nil
    }

    private func runKeywords(text: String, config: PolicyAnyCodable?) -> DetectorMatch? {
        guard let keywords = config?.value.asStringArray else { return nil }
        let lower = text.lowercased()
        for kw in keywords where !kw.isEmpty {
            if lower.contains(kw.lowercased()) {
                return DetectorMatch(
                    matchedSubstring: kw,
                    confidence: 0.95,
                    explanation: "Matched keyword \"\(kw)\""
                )
            }
        }
        return nil
    }

    private func runPIIDetector(text: String) -> DetectorMatch? {
        let matches = PIIDetector.findMatches(in: text, firstOnly: true)
        guard let first = matches.first else { return nil }
        return DetectorMatch(
            matchedSubstring: String(text[first.range]),
            confidence: 0.9,
            explanation: "Detected \(first.category.rawValue.uppercased())"
        )
    }

    private func runSecretsScanner(text: String) -> DetectorMatch? {
        // Reuses the apiKey + jwt buckets in PIIDetector, plus a private-key
        // marker the dashboard cares about.
        let hits = PIIDetector.findMatches(in: text, firstOnly: false)
            .filter { $0.category == .apiKey || $0.category == .jwt || $0.category == .bitcoinAddress }
        if let first = hits.first {
            return DetectorMatch(
                matchedSubstring: String(text[first.range]),
                confidence: 1.0,
                explanation: "Secret detected (\(first.category.rawValue))"
            )
        }
        if text.contains("-----BEGIN") && text.contains("PRIVATE KEY-----") {
            return DetectorMatch(
                matchedSubstring: "PRIVATE KEY block",
                confidence: 1.0,
                explanation: "PEM-formatted private key in prompt"
            )
        }
        return nil
    }

    private func runEntropy(text: String) -> DetectorMatch? {
        // High-entropy strings (>4.5 bits/char on tokens >=20 long) — same
        // heuristic as the dashboard simulator.
        let words = text.split(whereSeparator: { $0.isWhitespace })
        for word in words where word.count >= 20 {
            let entropy = Self.shannon(String(word))
            if entropy > 4.5 {
                return DetectorMatch(
                    matchedSubstring: String(word),
                    confidence: min(entropy / 6, 0.99),
                    explanation: "High-entropy string (entropy=\(String(format: "%.2f", entropy)))"
                )
            }
        }
        return nil
    }

    /// Lightweight stand-in for the dashboard's "ml-classifier" — looks for
    /// known prompt-injection vocabulary. Promptly defers true ML scoring
    /// to the cloud; this is the offline fallback.
    private func runHeuristicClassifier(
        text: String,
        detectorId: String,
        threshold: Double
    ) -> DetectorMatch? {
        let lower = text.lowercased()
        let vocab: [String: [String]] = [
            "ml-classifier": [
                "ignore previous", "disregard", "system prompt", "you are now",
                "developer mode", "jailbreak", "dan", "reveal your instructions"
            ],
            "toxicity-classifier": ["hate", "kill", "racist", "harassment"],
            "similarity-check": ["you are a", "your guidelines", "never discuss", "always respond"]
        ]
        let words = vocab[detectorId] ?? vocab["ml-classifier", default: []]
        var hits = 0
        var strongest = ""
        for w in words where lower.contains(w) {
            hits += 1
            if w.count > strongest.count { strongest = w }
        }
        let confidence = min(0.4 + Double(hits) * 0.2, 0.99)
        guard confidence >= threshold else { return nil }
        return DetectorMatch(
            matchedSubstring: strongest.isEmpty ? nil : strongest,
            confidence: confidence,
            explanation: "Classifier confidence \(String(format: "%.2f", confidence)) ≥ threshold \(String(format: "%.2f", threshold))"
        )
    }

    // MARK: - Action mapping

    private func mapEnforcement(_ mode: EnforcementMode, instance: PolicyInstance) -> PolicyDecision.Action {
        switch mode {
        case .log: return .log
        case .flag: return .flag
        case .redact: return .redact
        case .block: return .block(reason: instance.name)
        }
    }

    /// Strongest-wins precedence: `block > redact > flag > log > allow`.
    static func stronger(_ a: PolicyDecision.Action, _ b: PolicyDecision.Action) -> PolicyDecision.Action {
        rank(a) >= rank(b) ? a : b
    }

    private static func rank(_ action: PolicyDecision.Action) -> Int {
        switch action {
        case .allow: return 0
        case .log: return 1
        case .flag: return 2
        case .redact: return 3
        case .block: return 4
        }
    }

    // MARK: - Helpers

    private static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func shannon(_ s: String) -> Double {
        var freq: [Character: Int] = [:]
        for ch in s { freq[ch, default: 0] += 1 }
        let len = Double(s.count)
        var entropy = 0.0
        for (_, count) in freq {
            let p = Double(count) / len
            entropy -= p * log2(p)
        }
        return entropy
    }
}
