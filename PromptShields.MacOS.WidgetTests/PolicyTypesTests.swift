import XCTest
@testable import PromptShields_MacOS_Widget

/// Round-trip tests for the wire-format mirrors. The dashboard is the
/// source of truth — these tests pin Promptly to the exact JSON shapes
/// it emits so a rename in the TS schema is caught at the Swift layer.
final class PolicyTypesTests: XCTestCase {

    func testActivePoliciesResponseDecodesDashboardJSON() throws {
        // Shape lifted directly from the dashboard's `cloneFromTemplate`
        // output + `getTemplateById` for the OWASP LLM02 PII-Output entry.
        let json = """
        {
          "instances": [{
            "id": "policy-123-abc",
            "name": "Block PII in customer-facing prompts",
            "templateId": "owasp-llm02-pii-output",
            "templateVersion": "1.0.0",
            "parameterValues": {
              "pii_confidence": 0.85,
              "redact_categories": ["EMAIL", "PHONE", "PERSON"]
            },
            "enforcementMode": "redact",
            "severity": "high",
            "appliesTo": {
              "applicationIds": ["chatgpt", "claude"],
              "dataClassifications": ["pii"],
              "riskTiers": ["high"],
              "departments": []
            },
            "allowList": [],
            "status": "active",
            "createdBy": "alice@example.com",
            "createdAt": "2026-04-23T10:00:00Z",
            "updatedAt": "2026-04-23T10:00:00Z"
          }],
          "templates": [{
            "id": "owasp-llm02-pii-output",
            "name": "Sensitive Info Disclosure",
            "version": "1.0.0",
            "category": "OWASP_LLM",
            "severity": "high",
            "description": "Prevents PII from leaving via LLM responses.",
            "rationale": "LLMs can echo training-data PII if not constrained.",
            "owaspReference": "LLM02",
            "regulatoryReferences": ["GDPR Art. 5", "CCPA 1798.100"],
            "triggers": [{"stage": "input", "description": "Inbound prompts"}],
            "detectors": [
              {"id": "pii-named-entity", "type": "pii_detector", "description": "NER", "configRef": "pii_confidence"},
              {"id": "pii-regex", "type": "regex", "description": "Patterns", "configRef": "pii_patterns"}
            ],
            "actions": [{"type": "redact", "description": "Replace with placeholders"}],
            "tags": ["pii", "owasp"]
          }],
          "snapshotAt": "2026-04-23T10:05:12Z"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ActivePoliciesResponse.self, from: json)
        XCTAssertEqual(decoded.instances.count, 1)
        XCTAssertEqual(decoded.instances[0].enforcementMode, .redact)
        XCTAssertEqual(decoded.instances[0].severity, .high)
        XCTAssertEqual(decoded.instances[0].appliesTo.applicationIds, ["chatgpt", "claude"])

        let template = decoded.templates[0]
        XCTAssertEqual(template.category, .owaspLLM)
        XCTAssertEqual(template.detectors.first?.type, .piiDetector)
        XCTAssertEqual(template.triggers.first?.stage, .input)
    }

    func testParameterValuesRoundTrip() throws {
        // AnyCodable must round-trip the dashboard's mixed-type
        // `parameterValues` dict (number, list, bool).
        let payload: [String: Any] = [
            "pii_confidence": 0.85,
            "redact_categories": ["EMAIL", "PHONE"],
            "log_only": true,
            "max_requests_per_minute": 60
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["pii_confidence"]?.value.asDouble, 0.85)
        XCTAssertEqual(decoded["redact_categories"]?.value.asStringArray, ["EMAIL", "PHONE"])
        XCTAssertEqual(decoded["max_requests_per_minute"]?.value.asInt, 60)

        let reencoded = try JSONEncoder().encode(decoded)
        let again = try JSONDecoder().decode([String: AnyCodable].self, from: reencoded)
        XCTAssertEqual(again["pii_confidence"]?.value.asDouble, 0.85)
    }

    func testSeverityComparisonForStrongestWinsMerging() {
        XCTAssertLessThan(PolicySeverity.low, .medium)
        XCTAssertLessThan(PolicySeverity.medium, .high)
        XCTAssertLessThan(PolicySeverity.high, .critical)
    }

    func testAppliesToAppMatching() {
        let withApps = makeInstance(applicationIds: ["chatgpt", "claude"])
        XCTAssertTrue(withApps.appliesToApp(id: "chatgpt"))
        XCTAssertFalse(withApps.appliesToApp(id: "notion"))

        let withoutApps = makeInstance(applicationIds: [])
        XCTAssertTrue(withoutApps.appliesToApp(id: "anything"),
                      "Empty applicationIds means the instance applies globally")
    }

    // MARK: - helpers

    private func makeInstance(applicationIds: [String]) -> PolicyInstance {
        PolicyInstance(
            id: "i", name: "n", templateId: "t", templateVersion: "1",
            parameterValues: [:], enforcementMode: .log, severity: .low,
            appliesTo: PolicyInstanceAppliesTo(
                applicationIds: applicationIds,
                dataClassifications: [], riskTiers: [], departments: []
            ),
            allowList: [], status: .active,
            createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z"
        )
    }
}
