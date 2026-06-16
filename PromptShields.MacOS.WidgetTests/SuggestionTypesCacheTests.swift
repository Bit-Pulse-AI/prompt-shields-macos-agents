import XCTest
@testable import PromptShields_MacOS_Widget

/// Tests the cache-freshness primitive that prevents Settings from
/// re-fetching suggestion types on every appear. The TTL gate itself
/// lives in `SuggestionDomainServiceImpl.fetchSuggestionTypes()`; this
/// suite exercises the static helper so we can verify the policy
/// without mocking the entire domain stack.
final class SuggestionTypesCacheTests: XCTestCase {

    private let key = "ai.bit-pulse.promptshields.suggestionTypesFetchedAt"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testFreshFlagFalseWhenNeverFetched() {
        XCTAssertFalse(SuggestionDomainServiceImpl.isSuggestionTypesCacheFresh(),
                       "Fresh install must miss the cache so types are fetched once")
    }

    func testFreshFlagTrueImmediatelyAfterFetch() {
        UserDefaults.standard.set(Date(), forKey: key)
        XCTAssertTrue(SuggestionDomainServiceImpl.isSuggestionTypesCacheFresh())
    }

    func testFreshFlagFalseAfterTTLExpires() {
        // 6 minutes ago — beyond the 5-minute TTL.
        let stale = Date().addingTimeInterval(-360)
        UserDefaults.standard.set(stale, forKey: key)
        XCTAssertFalse(SuggestionDomainServiceImpl.isSuggestionTypesCacheFresh(),
                       "Cache marker older than TTL must miss")
    }

    func testFreshFlagFalseWhenStoredValueIsBogus() {
        // Defensive: if something stomps the value with a non-Date type,
        // the helper must err on the side of refetching.
        UserDefaults.standard.set("not-a-date", forKey: key)
        XCTAssertFalse(SuggestionDomainServiceImpl.isSuggestionTypesCacheFresh())
    }
}
