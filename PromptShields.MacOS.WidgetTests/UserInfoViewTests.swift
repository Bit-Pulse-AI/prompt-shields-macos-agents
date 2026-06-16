import XCTest
@testable import PromptShields_MacOS_Widget

/// Tests the name-fallback logic that resolves Henrik's PS-14 "n/a n/a" bug.
/// The chain is:
///   1. firstName + lastName if either is meaningful
///   2. email
///   3. "—"  (never "n/a", "null", "undefined", or empty)
final class UserInfoViewTests: XCTestCase {

    private func makeUser(
        firstName: String,
        lastName: String,
        email: String = "user@example.com"
    ) -> User.UserModel {
        User.UserModel(
            uuid: "test-uuid",
            email: email,
            firstName: firstName,
            lastName: lastName,
            photoURL: nil,
            profileId: nil,
            preferenceId: nil,
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    // MARK: - Happy path

    func testBothNamesPresent() {
        let u = makeUser(firstName: "Henrik", lastName: "Hesle")
        let r = UserInfoView.resolveDisplayName(from: u)
        XCTAssertEqual(r.name, "Henrik Hesle")
        XCTAssertEqual(r.initials, "HH")
    }

    func testOnlyFirstName() {
        let u = makeUser(firstName: "Henrik", lastName: "")
        let r = UserInfoView.resolveDisplayName(from: u)
        XCTAssertEqual(r.name, "Henrik")
        XCTAssertEqual(r.initials, "H")
    }

    func testOnlyLastName() {
        let u = makeUser(firstName: "", lastName: "Hesle")
        let r = UserInfoView.resolveDisplayName(from: u)
        XCTAssertEqual(r.name, "Hesle")
        XCTAssertEqual(r.initials, "H")
    }

    // MARK: - The "n/a" bug Henrik hit

    func testBothNamesLiterallyNASlashA() {
        // UserPersistentModel.swift defaults firstName and lastName to "n/a".
        // Before the fix, the UI displayed "n/a n/a". The fallback chain must
        // treat "n/a" as empty and fall through to email.
        let u = makeUser(firstName: "n/a", lastName: "n/a", email: "henrik@example.com")
        let r = UserInfoView.resolveDisplayName(from: u)
        XCTAssertNotEqual(r.name, "n/a n/a", "PS-14 regression: 'n/a n/a' must never render")
        XCTAssertEqual(r.name, "henrik@example.com")
    }

    func testNullValuesTreatedAsEmpty() {
        for junk in ["null", "undefined", "nil", "N/A"] {
            let u = makeUser(firstName: junk, lastName: junk, email: "user@example.com")
            let r = UserInfoView.resolveDisplayName(from: u)
            XCTAssertFalse(r.name.contains(junk),
                           "Junk value '\(junk)' leaked into display name")
        }
    }

    // MARK: - Email fallback

    func testEmailFallbackWhenNamesEmpty() {
        let u = makeUser(firstName: "", lastName: "", email: "user@example.com")
        let r = UserInfoView.resolveDisplayName(from: u)
        XCTAssertEqual(r.name, "user@example.com")
        XCTAssertEqual(r.initials, "US", "Email username 'user' should yield 'US' (first 2 letters)")
    }

    func testEmailFallbackWithDotUsername() {
        let u = makeUser(firstName: "", lastName: "", email: "henrik.hesle@example.com")
        let r = UserInfoView.resolveDisplayName(from: u)
        XCTAssertEqual(r.name, "henrik.hesle@example.com")
        XCTAssertEqual(r.initials, "HH", "Dotted username parts map to two initials")
    }

    // MARK: - Terminal fallback

    func testEmDashWhenEverythingEmpty() {
        let u = makeUser(firstName: "", lastName: "", email: "")
        let r = UserInfoView.resolveDisplayName(from: u)
        XCTAssertEqual(r.name, "—", "Terminal fallback is em-dash, never 'n/a'")
        XCTAssertEqual(r.initials, "—")
    }

    func testWhitespaceOnlyNamesCollapse() {
        let u = makeUser(firstName: "   ", lastName: "\t", email: "")
        let r = UserInfoView.resolveDisplayName(from: u)
        XCTAssertEqual(r.name, "—")
    }
}
