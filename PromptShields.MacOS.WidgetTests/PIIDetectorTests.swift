import XCTest
@testable import PromptShields_MacOS_Widget

/// Tests for the local `PIIDetector` that gates the Redaction-first UX.
///
/// The detector is deliberately high-recall: a false positive just means
/// the user sees a Redaction suggestion they can ignore, but a false
/// negative means PII leaks to the LLM. So tests prioritise "does it
/// catch the obvious stuff" and "does it not trigger on plain prose".
final class PIIDetectorTests: XCTestCase {

    // MARK: - Positive cases

    func testEmail() {
        XCTAssertTrue(PIIDetector.containsPII("ping anna.berg@clientcorp.com"))
        XCTAssertTrue(PIIDetector.containsPII("User: HENRIK.HESLE@EXAMPLE.COM"))
    }

    func testPhone() {
        XCTAssertTrue(PIIDetector.containsPII("call +47 912 34 567 after lunch"))
        XCTAssertTrue(PIIDetector.containsPII("reach me at 415-555-0100"))
    }

    func testCreditCardWithLuhn() {
        // 4111 1111 1111 1111 is the canonical Visa test number (Luhn-valid).
        XCTAssertTrue(PIIDetector.containsPII("card number 4111 1111 1111 1111 for the refund"))
    }

    func testCreditCardRejectsLuhnInvalid() {
        // All ones — not a real card, Luhn rejects.
        XCTAssertFalse(PIIDetector.containsPII("1111 1111 1111 1111 order #"))
    }

    func testSSN() {
        XCTAssertTrue(PIIDetector.containsPII("SSN 123-45-6789"))
    }

    func testAPIKeys() {
        XCTAssertTrue(PIIDetector.containsPII("openai sk-proj-abc123def456ghi789jkl"))
        XCTAssertTrue(PIIDetector.containsPII("aws key AKIAIOSFODNN7EXAMPLE"))
        XCTAssertTrue(PIIDetector.containsPII("github token ghp_1234567890abcdefghij1234567890abcdefgh"))
    }

    func testJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0JhSCH6uQu4nQzZqY"
        XCTAssertTrue(PIIDetector.containsPII("auth header: \(jwt)"))
    }

    func testIBAN() {
        XCTAssertTrue(PIIDetector.containsPII("send to NO9386011117947"))
    }

    func testIPv4() {
        XCTAssertTrue(PIIDetector.containsPII("server at 192.168.1.100"))
    }

    func testCurrency() {
        XCTAssertTrue(PIIDetector.containsPII("revenue €2.4M last quarter"))
        XCTAssertTrue(PIIDetector.containsPII("budget is $45,000"))
        XCTAssertTrue(PIIDetector.containsPII("contract value NOK 12M"))
    }

    func testPersonNameSoftSignal() {
        XCTAssertTrue(PIIDetector.containsPII("ping Anna Berg about the Q3 deck"))
    }

    // MARK: - Henrik's canonical prompt

    /// The exact PRD before-example for the Sanitise/Redaction type must
    /// trigger detection — otherwise the aha-moment demo falls flat.
    func testHenrikCanonicalPrompt() {
        let prompt = "Write a cold email to john.smith@clientcorp.com about our Q3 results showing €2.4M revenue. CEO Anna Berg wants to close by Friday."
        let matches = PIIDetector.findMatches(in: prompt)
        let categories = Set(matches.map(\.category))
        XCTAssertTrue(categories.contains(.email), "Henrik's email must be caught")
        XCTAssertTrue(categories.contains(.currency), "Revenue figure must be caught")
        XCTAssertTrue(categories.contains(.personName), "CEO name must be caught as soft signal")
    }

    // MARK: - Negative cases

    func testPlainProseDoesNotTrigger() {
        let inputs = [
            "Write a summary of the quarterly trends.",
            "Please explain the concept of machine learning.",
            "Can you help me improve this paragraph?",
            "Lorem ipsum dolor sit amet consectetur.",
            "New York and San Francisco are expensive."
        ]
        for s in inputs {
            XCTAssertFalse(PIIDetector.containsPII(s), "False positive on: \(s)")
        }
    }

    func testEmptyInput() {
        XCTAssertFalse(PIIDetector.containsPII(""))
        XCTAssertTrue(PIIDetector.findMatches(in: "").isEmpty)
    }

    func testExcessivelyLongInputIsSkipped() {
        let huge = String(repeating: "a@b.com ", count: 20_000) // > 50kB
        // Safety rail short-circuits to avoid regex pathology.
        XCTAssertFalse(PIIDetector.containsPII(huge))
    }

    // MARK: - findMatches granularity

    func testFindMatchesReturnsSpans() {
        let text = "contact anna.berg@example.com"
        let matches = PIIDetector.findMatches(in: text)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.category, .email)
        let matched = text[matches[0].range]
        XCTAssertEqual(String(matched), "anna.berg@example.com")
    }

    func testFirstOnlyShortCircuits() {
        let text = "anna.berg@example.com and +1 415 555 0100"
        let all = PIIDetector.findMatches(in: text, firstOnly: false)
        let first = PIIDetector.findMatches(in: text, firstOnly: true)
        XCTAssertGreaterThanOrEqual(all.count, 2)
        XCTAssertEqual(first.count, 1)
    }
}
