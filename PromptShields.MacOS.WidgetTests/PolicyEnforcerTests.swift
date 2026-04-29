import XCTest
@testable import PromptShields_MacOS_Widget

/// Functional tests for `PolicyEnforcer`. Uses an in-memory `PolicyClient`
/// seeded with synthetic policies — no network or AXObserver needed.
@MainActor
final class PolicyEnforcerTests: XCTestCase {

    // MARK: - Test scaffolding

    private func makeClient(
        instances: [PolicyInstance] = [],
        templates: [PolicyTemplate] = []
    ) async -> PolicyClient {
        let transport = StubTransport(
            response: ActivePoliciesResponse(
                instances: instances,
                templates: templates,
                snapshotAt: "2026-04-23T10:00:00Z"
            )
        )
        let client = PolicyClient(transport: transport, refreshInterval: 999)
        await client.refresh()
        return client
    }

    private func instance(
        id: String = "i-1",
        templateId: String,
        enforcement: EnforcementMode,
        severity: PolicySeverity = .high,
        appIds: [String] = [],
        params: [String: AnyCodableValue] = [:]
    ) -> PolicyInstance {
        PolicyInstance(
            id: id, name: id, templateId: templateId, templateVersion: "1.0",
            parameterValues: params.mapValues { AnyCodable($0) },
            enforcementMode: enforcement, severity: severity,
            appliesTo: PolicyInstanceAppliesTo(
                applicationIds: appIds, dataClassifications: [],
                riskTiers: [], departments: []
            ),
            allowList: [], status: .active,
            createdAt: "2026-01-01T00:00:00Z", updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    private func template(
        id: String,
        detectors: [PolicyDetector],
        triggers: [PolicyTrigger] = [PolicyTrigger(stage: .input, description: "Input prompts")]
    ) -> PolicyTemplate {
        PolicyTemplate(
            id: id, name: id, version: "1.0", category: .owaspLLM, severity: .high,
            description: "", rationale: "", triggers: triggers, detectors: detectors,
            actions: [], regulatoryReferences: [], owaspReference: nil, tags: []
        )
    }

    // MARK: - Allow path

    func testAllowsWhenNoPoliciesActive() async {
        let client = await makeClient()
        let enforcer = PolicyEnforcer(client: client)
        let decision = enforcer.evaluate(text: "Just normal prose.", appId: "chatgpt")
        XCTAssertEqual(decision.action, .allow)
        XCTAssertTrue(decision.triggered.isEmpty)
    }

    func testAllowsEmptyText() async {
        let t = template(id: "t1", detectors: [
            PolicyDetector(id: "d1", type: .piiDetector, description: "", configRef: "x")
        ])
        let client = await makeClient(
            instances: [instance(templateId: "t1", enforcement: .block)],
            templates: [t]
        )
        let enforcer = PolicyEnforcer(client: client)
        XCTAssertEqual(enforcer.evaluate(text: "", appId: "chatgpt").action, .allow)
    }

    // MARK: - PII detector

    func testPIIDetectorTriggersConfiguredEnforcement() async {
        let t = template(id: "t-pii", detectors: [
            PolicyDetector(id: "pii-named-entity", type: .piiDetector, description: "", configRef: "x")
        ])
        let i = instance(templateId: "t-pii", enforcement: .redact)
        let client = await makeClient(instances: [i], templates: [t])
        let enforcer = PolicyEnforcer(client: client)

        let decision = enforcer.evaluate(
            text: "Email me at anna.berg@example.com",
            appId: "chatgpt"
        )
        XCTAssertEqual(decision.action, .redact)
        XCTAssertEqual(decision.triggered.first?.detectorId, "pii-named-entity")
    }

    // MARK: - Regex detector

    func testRegexDetectorMatchesPatterns() async {
        let t = template(id: "t-regex", detectors: [
            PolicyDetector(id: "internal-name", type: .regex, description: "", configRef: "patterns")
        ])
        let i = instance(
            templateId: "t-regex",
            enforcement: .flag,
            params: ["patterns": .array([.string("Project [A-Z]+\\d+")])]
        )
        let client = await makeClient(instances: [i], templates: [t])
        let enforcer = PolicyEnforcer(client: client)

        let hit = enforcer.evaluate(text: "context Project APOLLO11 status", appId: "chatgpt")
        XCTAssertEqual(hit.action, .flag)
        XCTAssertEqual(hit.triggered.first?.matchedSubstring, "Project APOLLO11")

        let miss = enforcer.evaluate(text: "no codename here", appId: "chatgpt")
        XCTAssertEqual(miss.action, .allow)
    }

    // MARK: - Keyword detector

    func testKeywordDetectorIsCaseInsensitive() async {
        let t = template(id: "t-kw", detectors: [
            PolicyDetector(id: "secret-words", type: .keywordList, description: "", configRef: "kws")
        ])
        let i = instance(
            templateId: "t-kw",
            enforcement: .block,
            params: ["kws": .array([.string("merger"), .string("acquisition")])]
        )
        let client = await makeClient(instances: [i], templates: [t])
        let enforcer = PolicyEnforcer(client: client)

        let decision = enforcer.evaluate(text: "Update on the MERGER deal", appId: "chatgpt")
        if case .block(let reason) = decision.action {
            XCTAssertEqual(reason, "i-1")
        } else {
            XCTFail("Expected block action, got \(decision.action)")
        }
    }

    // MARK: - Strongest-wins merging

    func testStrongestActionWinsAcrossMultipleInstances() async {
        let tFlag = template(id: "t-flag", detectors: [
            PolicyDetector(id: "kw1", type: .keywordList, description: "", configRef: "k")
        ])
        let tRedact = template(id: "t-redact", detectors: [
            PolicyDetector(id: "pii1", type: .piiDetector, description: "", configRef: "x")
        ])
        let tBlock = template(id: "t-block", detectors: [
            PolicyDetector(id: "secret1", type: .secretsScanner, description: "", configRef: "x")
        ])
        let client = await makeClient(
            instances: [
                instance(id: "flag-i", templateId: "t-flag", enforcement: .flag,
                         params: ["k": .array([.string("merger")])]),
                instance(id: "redact-i", templateId: "t-redact", enforcement: .redact),
                instance(id: "block-i", templateId: "t-block", enforcement: .block)
            ],
            templates: [tFlag, tRedact, tBlock]
        )
        let enforcer = PolicyEnforcer(client: client)

        // Hit all three: keyword + email (PII) + AWS key (secret).
        let text = "Re: merger — email anna@example.com — AKIAIOSFODNN7EXAMPLE"
        let decision = enforcer.evaluate(text: text, appId: "chatgpt")

        if case .block = decision.action {
            // expected
        } else {
            XCTFail("Strongest should be block, got \(decision.action)")
        }
        XCTAssertGreaterThanOrEqual(decision.triggered.count, 3)
    }

    // MARK: - App scope

    func testInstancesScopedToOtherAppsAreIgnored() async {
        let t = template(id: "t-scoped", detectors: [
            PolicyDetector(id: "pii", type: .piiDetector, description: "", configRef: "x")
        ])
        let i = instance(templateId: "t-scoped", enforcement: .block, appIds: ["claude"])
        let client = await makeClient(instances: [i], templates: [t])
        let enforcer = PolicyEnforcer(client: client)

        let chatGPTDecision = enforcer.evaluate(
            text: "email anna@example.com", appId: "chatgpt"
        )
        XCTAssertEqual(chatGPTDecision.action, .allow,
                       "Policy scoped to claude must not fire on chatgpt")

        let claudeDecision = enforcer.evaluate(
            text: "email anna@example.com", appId: "claude"
        )
        XCTAssertEqual(claudeDecision.action, .block(reason: "i-1"))
    }

    // MARK: - Hashing

    func testPromptHashIsStableAndNotRawText() async {
        let client = await makeClient()
        let enforcer = PolicyEnforcer(client: client)
        let raw = "very sensitive secret"
        let decision1 = enforcer.evaluate(text: raw, appId: "chatgpt")
        let decision2 = enforcer.evaluate(text: raw, appId: "chatgpt")
        XCTAssertEqual(decision1.promptHash, decision2.promptHash)
        XCTAssertEqual(decision1.promptHash.count, 64, "SHA-256 hex is 64 chars")
        XCTAssertFalse(decision1.promptHash.contains("sensitive"))
    }

    func testStrongerActionPrecedence() {
        let stronger = PolicyEnforcer.stronger
        XCTAssertEqual(stronger(.allow, .log), .log)
        XCTAssertEqual(stronger(.log, .flag), .flag)
        XCTAssertEqual(stronger(.flag, .redact), .redact)
        XCTAssertEqual(stronger(.redact, .block(reason: "x")), .block(reason: "x"))
        XCTAssertEqual(stronger(.block(reason: "a"), .allow), .block(reason: "a"))
    }
}

// MARK: - Stub transport

private struct StubTransport: PolicyTransport {
    let response: ActivePoliciesResponse
    func fetchActivePolicies() async throws -> ActivePoliciesResponse { response }
    func reportViolation(_ violation: PolicyViolation) async throws {}
}
