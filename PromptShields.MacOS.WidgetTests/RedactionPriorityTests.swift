import XCTest
@testable import PromptShields_MacOS_Widget

/// Tests the Redaction-first UX promise: when `PIIDetector` flags the
/// focused text, the Redaction suggestion must appear at the top of the
/// list regardless of its stored `sortOrder`, and the amber banner logic
/// must fire. Builds against `ActionView.isRedactionType` — the same
/// matcher the real UI uses.
final class RedactionPriorityTests: XCTestCase {

    private func makeType(typeKey: String, name: String, sortOrder: Int = 0) -> SuggestionType {
        SuggestionType(model: .init(
            uuid: UUID().uuidString,
            typeKey: typeKey,
            name: name,
            description: "",
            category: "Security & Compliance",
            promptTemplate: "",
            suggestionTypeGroupId: "",
            isDefault: false,
            isEnabled: true,
            sortOrder: sortOrder,
            createdAt: nil,
            updatedAt: nil
        ))
    }

    // MARK: - isRedactionType matcher

    func testRedactionTypeKeyMatches() {
        XCTAssertTrue(ActionView.isRedactionType(makeType(typeKey: "redaction", name: "Redaction")))
        XCTAssertTrue(ActionView.isRedactionType(makeType(typeKey: "REDACTION", name: "Whatever")))
        XCTAssertTrue(ActionView.isRedactionType(makeType(typeKey: "redact_pii", name: "Redact PII")))
        XCTAssertTrue(ActionView.isRedactionType(makeType(typeKey: "", name: "Redact sensitive data")))
    }

    func testNonRedactionTypes() {
        XCTAssertFalse(ActionView.isRedactionType(makeType(typeKey: "sanitise", name: "Sanitise")))
        XCTAssertFalse(ActionView.isRedactionType(makeType(typeKey: "detect_risk", name: "Detect Risk")))
        XCTAssertFalse(ActionView.isRedactionType(makeType(typeKey: "shorten", name: "Shorten")))
    }

    // MARK: - Reorder logic (replicates ActionView.suggestionTypes)

    /// Mirrors the sort used in ActionView so we can test it without
    /// instantiating SwiftUI state.
    private func reorder(_ types: [SuggestionType], piiDetected: Bool) -> [SuggestionType] {
        types.sorted { lhs, rhs in
            if piiDetected {
                let lhsRedacts = ActionView.isRedactionType(lhs)
                let rhsRedacts = ActionView.isRedactionType(rhs)
                if lhsRedacts != rhsRedacts { return lhsRedacts }
            }
            return lhs.model.sortOrder < rhs.model.sortOrder
        }
    }

    func testRedactionFloatsToTopWhenPIIDetected() {
        let types = [
            makeType(typeKey: "shorten", name: "Shorten", sortOrder: 0),
            makeType(typeKey: "redaction", name: "Redaction", sortOrder: 99),
            makeType(typeKey: "optimise", name: "Optimise", sortOrder: 1)
        ]
        let sorted = reorder(types, piiDetected: true)
        XCTAssertEqual(sorted.first?.model.typeKey, "redaction",
                       "Redaction must win the first slot regardless of high sortOrder")
    }

    func testRedactionHonoursSortOrderWhenNoPII() {
        let types = [
            makeType(typeKey: "shorten", name: "Shorten", sortOrder: 0),
            makeType(typeKey: "redaction", name: "Redaction", sortOrder: 99),
            makeType(typeKey: "optimise", name: "Optimise", sortOrder: 1)
        ]
        let sorted = reorder(types, piiDetected: false)
        XCTAssertEqual(sorted.first?.model.typeKey, "shorten",
                       "Without PII signal, sortOrder takes over — Redaction isn't forced first")
        XCTAssertEqual(sorted.last?.model.typeKey, "redaction")
    }

    func testOriginalOrderPreservedAmongNonRedactionTypes() {
        let types = [
            makeType(typeKey: "shorten", name: "Shorten", sortOrder: 10),
            makeType(typeKey: "redaction", name: "Redaction", sortOrder: 99),
            makeType(typeKey: "simplify", name: "Simplify", sortOrder: 5),
            makeType(typeKey: "optimise", name: "Optimise", sortOrder: 1)
        ]
        let sorted = reorder(types, piiDetected: true)
        XCTAssertEqual(sorted[0].model.typeKey, "redaction")
        XCTAssertEqual(sorted[1].model.typeKey, "optimise", "sortOrder=1 next")
        XCTAssertEqual(sorted[2].model.typeKey, "simplify", "sortOrder=5 next")
        XCTAssertEqual(sorted[3].model.typeKey, "shorten", "sortOrder=10 last")
    }
}
