import XCTest
@testable import PromptShields_MacOS_Widget

/// Pins the `focusedURLHost` extraction logic — AI-SPM uses this to
/// scope per-domain rules and the Ardoq export relies on it for the
/// "where" column.
final class ElementInfoURLTests: XCTestCase {

    private func makeInfo(focusedURL: String?) -> ElementInfo {
        ElementInfo(
            text: "anything",
            applicationName: "Chrome",
            applicationBundleId: "com.google.Chrome",
            frame: .zero,
            elementIdentifier: nil,
            isSelectedText: false,
            focusedURL: focusedURL
        )
    }

    func testHostExtractedFromHTTPS() {
        XCTAssertEqual(
            makeInfo(focusedURL: "https://chat.openai.com/c/abc123").focusedURLHost,
            "chat.openai.com"
        )
    }

    func testHostExtractedFromHTTP() {
        XCTAssertEqual(
            makeInfo(focusedURL: "http://localhost:3000/admin").focusedURLHost,
            "localhost"
        )
    }

    func testHostLowercased() {
        XCTAssertEqual(
            makeInfo(focusedURL: "https://Claude.AI/new").focusedURLHost,
            "claude.ai"
        )
    }

    func testNilWhenURLAbsent() {
        XCTAssertNil(makeInfo(focusedURL: nil).focusedURLHost)
        XCTAssertNil(makeInfo(focusedURL: "").focusedURLHost)
    }

    func testNilWhenURLMalformed() {
        XCTAssertNil(makeInfo(focusedURL: "not a url").focusedURLHost)
    }

    func testHandlesQueryAndFragment() {
        XCTAssertEqual(
            makeInfo(focusedURL: "https://gemini.google.com/app?q=test#fragment").focusedURLHost,
            "gemini.google.com"
        )
    }
}
