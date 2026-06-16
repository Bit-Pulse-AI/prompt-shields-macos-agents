import Foundation

// Wire-format mirror of the AI-SPM dashboard's policy schema.
// Source of truth lives in `ai-spm-dashboard/lib/policy-templates/types.ts`
// — keep these in sync. The dashboard owns the *definition* of policies;
// Promptly is the on-device PEP (Policy Enforcement Point) that runs them.
//
// Encoded JSON is exchanged 1:1 with the Next.js API at
// `https://<dashboard>/api/policies` (active instances only) and
// `POST /api/policies/violations` (ingest from PEPs like Promptly).
//
// All types decode from the canonical TS shape via a CodingKey mapping
// rather than property renames, so that the Swift naming convention stays
// idiomatic.

// MARK: - Enumerations

enum PolicyCategory: String, Codable, Sendable {
    case owaspLLM = "OWASP_LLM"
    case euAIAct = "EU_AI_ACT"
    case gdpr = "GDPR"
    case industry = "INDUSTRY"
    case shadowAI = "SHADOW_AI"
    case contentSafety = "CONTENT_SAFETY"
    case custom = "CUSTOM"
}

enum PolicySeverity: String, Codable, Sendable, Comparable {
    case low, medium, high, critical

    /// Severity ordering for "highest wins" merging.
    static func < (lhs: PolicySeverity, rhs: PolicySeverity) -> Bool {
        let order: [PolicySeverity] = [.low, .medium, .high, .critical]
        let lhsIndex = order.firstIndex(of: lhs) ?? 0
        let rhsIndex = order.firstIndex(of: rhs) ?? 0
        return lhsIndex < rhsIndex
    }
}

enum EnforcementMode: String, Codable, Sendable {
    case log
    case flag
    case block
    case redact
}

enum TriggerStage: String, Codable, Sendable {
    case input
    case output
    case context
    case toolCall = "tool_call"
}

enum DetectorType: String, Codable, Sendable {
    case regex
    case keywordList = "keyword_list"
    case classifier
    case llmJudge = "llm_judge"
    case rateCounter = "rate_counter"
    case entropy
    case piiDetector = "pii_detector"
    case secretsScanner = "secrets_scanner"
}

enum ActionType: String, Codable, Sendable {
    case block
    case flag
    case log
    case redact
    case rewrite
    case notify
    case requireReview = "require_review"
    /// Promptly-emitted only — fires for `.allow` decisions so the
    /// dashboard has a denominator for false-positive rates. Not part of
    /// the original AI-SPM template/instance vocabulary.
    case evaluated
}

enum InstanceStatus: String, Codable, Sendable {
    case draft
    case testing
    case active
    case paused
    case archived
}

// MARK: - Trigger / Detector / Action / Parameter

struct PolicyTrigger: Codable, Sendable, Hashable {
    let stage: TriggerStage
    let description: String
}

struct PolicyDetector: Codable, Sendable, Hashable {
    let id: String
    let type: DetectorType
    let description: String
    let configRef: String
}

struct PolicyAction: Codable, Sendable, Hashable {
    let type: ActionType
    let description: String
    let configRef: String?
}

// MARK: - Policy Template (read-only)

struct PolicyTemplate: Codable, Sendable, Hashable {
    let id: String
    let name: String
    let version: String
    let category: PolicyCategory
    let severity: PolicySeverity
    let description: String
    let rationale: String
    let triggers: [PolicyTrigger]
    let detectors: [PolicyDetector]
    let actions: [PolicyAction]
    let regulatoryReferences: [String]
    let owaspReference: String?
    let tags: [String]
}

// MARK: - Policy Instance (user-tuned, deployed)

struct PolicyInstanceAppliesTo: Codable, Sendable, Hashable {
    let applicationIds: [String]
    let dataClassifications: [String]
    let riskTiers: [String]
    let departments: [String]
}

struct PolicyInstance: Codable, Sendable, Hashable {
    let id: String
    let name: String
    let templateId: String
    let templateVersion: String
    let parameterValues: [String: PolicyAnyCodable]
    let enforcementMode: EnforcementMode
    let severity: PolicySeverity
    let appliesTo: PolicyInstanceAppliesTo
    let allowList: [String]
    let status: InstanceStatus
    let createdAt: String
    let updatedAt: String

    /// Apps this policy targets, mapped from `appliesTo.applicationIds`.
    /// AI-SPM uses opaque IDs; Promptly uses MonitoredApp.id (chatgpt, claude,
    /// etc) — the dashboard publishes the same ID space for matching apps.
    func appliesToApp(id: String) -> Bool {
        appliesTo.applicationIds.isEmpty || appliesTo.applicationIds.contains(id)
    }
}

// MARK: - Active policies bundle (what the API returns)

/// Response shape for `GET /api/policies`. Bundles instances with their
/// templates so the PEP doesn't need a second round-trip per instance.
struct ActivePoliciesResponse: Codable, Sendable {
    let instances: [PolicyInstance]
    let templates: [PolicyTemplate]
    /// Server time when this snapshot was generated. Promptly uses it to
    /// detect policy drift — if the snapshot is older than the policy
    /// refresh interval, force a refetch on next evaluation.
    let snapshotAt: String
}

// MARK: - Violation report (PEP → dashboard)

/// What Promptly POSTs to `/api/policies/violations` after running a policy.
/// Crucially never includes the raw prompt — only a SHA-256 of the prompt
/// and the matched substring (capped at 200 chars). Audit logs must not
/// become a PII leak themselves.
struct PolicyViolation: Codable, Sendable, Hashable {
    let id: String
    let policyInstanceId: String
    let applicationId: String
    let timestamp: String
    let actionTaken: ActionType
    let severity: PolicySeverity
    let detectorId: String
    /// SHA-256 hex of the prompt at evaluation time. Never the raw text.
    let promptHash: String
    let user: String?
    let evidence: PolicyViolationEvidence
    let reviewed: Bool
}

struct PolicyViolationEvidence: Codable, Sendable, Hashable {
    let detectorOutput: String
    let matchedPattern: String?
    let confidence: Double?
    /// Optional URL host when the prompt was observed inside a browser
    /// tab. Lets the dashboard scope per-domain rules and shows up in the
    /// Ardoq export's "where" column. Nil for native-app sources.
    var urlHost: String?
}

// MARK: - PolicyAnyCodable

/// Lightweight Codable wrapper for the dashboard's
/// `parameterValues: Record<string, unknown>`. Decodes the JSON primitives
/// we actually consume — string, number, bool, list, dict — and round-trips
/// them. The dashboard side is JS so it'll never send anything more exotic.
struct PolicyAnyCodable: Codable, Sendable, Hashable {
    let value: PolicyAnyCodableValue

    init(_ value: PolicyAnyCodableValue) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = .null
        } else if let bool = try? container.decode(Bool.self) {
            self.value = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self.value = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self.value = .double(double)
        } else if let string = try? container.decode(String.self) {
            self.value = .string(string)
        } else if let array = try? container.decode([PolicyAnyCodable].self) {
            self.value = .array(array.map(\.value))
        } else if let dict = try? container.decode([String: PolicyAnyCodable].self) {
            self.value = .object(dict.mapValues(\.value))
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "PolicyAnyCodable: unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let arr): try container.encode(arr.map(PolicyAnyCodable.init))
        case .object(let dict): try container.encode(dict.mapValues(PolicyAnyCodable.init))
        }
    }
}

indirect enum PolicyAnyCodableValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([PolicyAnyCodableValue])
    case object([String: PolicyAnyCodableValue])

    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var asDouble: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    var asInt: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    var asStringArray: [String]? {
        guard case .array(let arr) = self else { return nil }
        return arr.compactMap {
            if case .string(let s) = $0 { return s } else { return nil }
        }
    }
}
