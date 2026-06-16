import XCTest
@testable import PromptShields_MacOS_Widget

/// Tests for `ActivityBadge` classification in the Activity Log (PS-12).
/// Every scanned suggestion is categorised into one of three badges based on
/// its `suggestionType` name. The matcher is case-insensitive and substring-
/// based so backend naming variations (e.g. "Detect Risk" vs "risk_detection")
/// still resolve correctly.
final class ActivityBadgeTests: XCTestCase {

    private func makeSuggestion(type: String) -> Suggestion {
        Suggestion(model: .init(
            uuid: UUID().uuidString,
            originalText: "irrelevant",
            suggestedText: "irrelevant",
            suggestionType: type,
            application: "TestApp",
            createdAt: Date()
        ))
    }

    // MARK: - Risk-class badges

    func testRiskKeywordClassifiesAsRiskCaught() {
        let s = makeSuggestion(type: "Detect Risk")
        XCTAssertEqual(ActivityBadge.for(suggestion: s), .riskCaught)
    }

    func testPolicyKeywordClassifiesAsRiskCaught() {
        let s = makeSuggestion(type: "Align with Policy")
        XCTAssertEqual(ActivityBadge.for(suggestion: s), .riskCaught)
    }

    func testGuardrailKeywordClassifiesAsRiskCaught() {
        let s = makeSuggestion(type: "Add Safety Guardrails")
        XCTAssertEqual(ActivityBadge.for(suggestion: s), .riskCaught)
    }

    // MARK: - Sanitised

    func testSanitiseClassifiesAsSanitised() {
        let s = makeSuggestion(type: "Sanitise")
        XCTAssertEqual(ActivityBadge.for(suggestion: s), .sanitised)
    }

    func testSanitizeAmericanSpellingAlsoMatches() {
        let s = makeSuggestion(type: "Sanitize")
        XCTAssertEqual(ActivityBadge.for(suggestion: s), .sanitised)
    }

    // MARK: - Everything else → optimised

    func testShortenClassifiesAsOptimised() {
        let s = makeSuggestion(type: "Shorten")
        XCTAssertEqual(ActivityBadge.for(suggestion: s), .optimised)
    }

    func testOptimiseForModelClassifiesAsOptimised() {
        let s = makeSuggestion(type: "Optimise for Model")
        XCTAssertEqual(ActivityBadge.for(suggestion: s), .optimised)
    }

    func testUnknownTypeFallsBackToOptimised() {
        let s = makeSuggestion(type: "some-future-category")
        XCTAssertEqual(ActivityBadge.for(suggestion: s), .optimised)
    }

    // MARK: - Substring + case tolerance

    func testCaseInsensitive() {
        let s = makeSuggestion(type: "DETECT_RISK")
        XCTAssertEqual(ActivityBadge.for(suggestion: s), .riskCaught)
    }

    func testSubstringMatchesBackendVariants() {
        // Backend might label things differently — substring match is the point.
        let variants = [
            "risk_detection", "PolicyViolation", "sanitization-step", "guardrails_applied"
        ]
        let expected: [ActivityBadge] = [.riskCaught, .riskCaught, .sanitised, .riskCaught]
        for (i, variant) in variants.enumerated() {
            let s = makeSuggestion(type: variant)
            XCTAssertEqual(ActivityBadge.for(suggestion: s), expected[i],
                           "Variant '\(variant)' classified incorrectly")
        }
    }

    // MARK: - Badge appearance (sanity checks)

    func testBadgeLabelsAreHuman() {
        XCTAssertEqual(ActivityBadge.riskCaught.label, "Risk caught")
        XCTAssertEqual(ActivityBadge.sanitised.label, "Sanitised")
        XCTAssertEqual(ActivityBadge.optimised.label, "Optimised")
    }
}
