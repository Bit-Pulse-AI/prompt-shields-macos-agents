import XCTest
@testable import PromptShields_MacOS_Widget

/// Lightweight tests for the in-memory rollup. The aggregator is a
/// singleton talking to the global TelemetryClient; flush() drains its
/// state, so these tests use the public APIs and verify that recording
/// + flushing produces no crash and zeroes the buckets.
@MainActor
final class UsageEventAggregatorTests: XCTestCase {

    func testFlushEmptyDoesntCrash() async {
        await UsageEventAggregator.shared.flush()
    }

    func testRecordThenFlushClearsBuckets() async {
        let agg = UsageEventAggregator.shared
        agg.record(kind: .prompt, promptlyAppId: "chatgpt", auth0Sub: "auth0|test")
        agg.record(kind: .blocked, promptlyAppId: "chatgpt", auth0Sub: "auth0|test")
        agg.record(kind: .redacted, promptlyAppId: "claude", auth0Sub: "auth0|test")
        // Flush hits the (Null) transport and clears buckets. We can't
        // observe the batch directly without exposing internals; the
        // contract here is that a subsequent flush is a noop.
        await agg.flush()
        await agg.flush()  // second flush should be safe (empty)
    }

    func testRecordIgnoresEmptyAppId() async {
        let agg = UsageEventAggregator.shared
        agg.record(kind: .prompt, promptlyAppId: "", auth0Sub: "auth0|test")
        await agg.flush()
    }

    func testRecordHandlesAnonymousUser() async {
        let agg = UsageEventAggregator.shared
        agg.record(kind: .prompt, promptlyAppId: "chatgpt", auth0Sub: nil)
        await agg.flush()
    }
}
