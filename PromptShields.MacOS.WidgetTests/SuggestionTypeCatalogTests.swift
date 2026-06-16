import XCTest
@testable import PromptShields_MacOS_Widget

/// Tests for `SuggestionTypeCatalog` (PS-10). The catalog is a display-time
/// overlay keyed by `typeKey` or `name` — we need matching to be tolerant to
/// case, whitespace, hyphens, and underscores so customer-imported data keys
/// still resolve.
final class SuggestionTypeCatalogTests: XCTestCase {

    // Minimal domain fixture.
    private func makeType(typeKey: String = "", name: String) -> SuggestionType {
        SuggestionType(model: .init(
            uuid: UUID().uuidString,
            typeKey: typeKey,
            name: name,
            description: "",
            category: "Custom",
            promptTemplate: "",
            suggestionTypeGroupId: "",
            isDefault: false,
            isEnabled: true,
            sortOrder: 0,
            createdAt: nil,
            updatedAt: nil
        ))
    }

    // MARK: - typeKey lookups

    func testTypeKeyLookupMatchesSnakeCase() {
        let t = makeType(typeKey: "detect_risk", name: "Anything")
        XCTAssertEqual(SuggestionTypeCatalog.metadata(for: t)?.emoji, "🛡️")
    }

    func testTypeKeyLookupMatchesSpacedVariant() {
        let t = makeType(typeKey: "detect risk", name: "Anything")
        XCTAssertEqual(SuggestionTypeCatalog.metadata(for: t)?.emoji, "🛡️")
    }

    func testTypeKeyLookupMatchesHyphenated() {
        let t = makeType(typeKey: "detect-risk", name: "Anything")
        XCTAssertEqual(SuggestionTypeCatalog.metadata(for: t)?.emoji, "🛡️")
    }

    // MARK: - name lookups (fallback when typeKey missing)

    func testNameLookupFallback() {
        let t = makeType(typeKey: "", name: "Sanitise")
        let meta = SuggestionTypeCatalog.metadata(for: t)
        XCTAssertNotNil(meta, "Catalog should fall back to name when typeKey is empty")
        XCTAssertTrue(meta?.before.contains("Anna Berg") ?? false,
                      "Sanitise's PRD before-example must be present")
    }

    func testNameLookupIsCaseInsensitive() {
        let upper = makeType(name: "SANITISE")
        let lower = makeType(name: "sanitise")
        XCTAssertEqual(SuggestionTypeCatalog.metadata(for: upper)?.emoji,
                       SuggestionTypeCatalog.metadata(for: lower)?.emoji)
    }

    func testNameAcceptsAmericanSpelling() {
        let us = makeType(name: "Sanitize")
        XCTAssertNotNil(SuggestionTypeCatalog.metadata(for: us),
                        "Catalog must accept 'sanitize' and 'sanitise' interchangeably")
    }

    // MARK: - Miss behavior

    func testUnknownTypeReturnsNil() {
        let t = makeType(name: "Fizzbuzz")
        XCTAssertNil(SuggestionTypeCatalog.metadata(for: t))
    }

    // MARK: - Coverage

    func testAllThirteenPRDTypesPresent() {
        let names = [
            "Detect Risk", "Optimise for Model", "Shorten", "Align with Policy",
            "Translate", "Rephrase for Role", "Simplify", "Format Output",
            "Elaborate", "Combine Prompts", "Formalise", "Add Safety Guardrails",
            "Sanitise"
        ]
        for name in names {
            let t = makeType(name: name)
            XCTAssertNotNil(SuggestionTypeCatalog.metadata(for: t),
                            "PRD type '\(name)' missing from catalog")
        }
    }
}
