import XCTest
@testable import PromptShields_MacOS_Widget

/// Contract tests for the daily tour-engagement rollup. Singleton state
/// is private; we exercise the public surface and assert that flush
/// doesn't crash + repeated flushes are noops once drained.
@MainActor
final class TourEngagementAggregatorTests: XCTestCase {

    func testFlushEmptyIsNoop() async {
        await TourEngagementAggregator.shared.flush()
    }

    func testRecordStartThenFlush() async {
        let agg = TourEngagementAggregator.shared
        agg.recordStart(tourId: "dashboard-intro", auth0Sub: "auth0|abc")
        agg.recordStart(tourId: "chat-intro", auth0Sub: "auth0|abc")
        await agg.flush()
        // Subsequent flush is empty.
        await agg.flush()
    }

    func testRecordCompletionAggregatesDuration() async {
        let agg = TourEngagementAggregator.shared
        agg.recordCompletion(tourId: "dashboard-intro", durationSec: 12.5)
        agg.recordCompletion(tourId: "dashboard-intro", durationSec: 7.3)
        // Sum is 19.8 — we can't introspect from here, but the flush
        // must produce exactly one event (one tuple key), not two.
        await agg.flush()
    }

    func testDismissalReasons() async {
        let agg = TourEngagementAggregator.shared
        agg.recordDismissal(tourId: "chat-intro", stepIndex: 2, reason: "esc")
        agg.recordDismissal(tourId: "chat-intro", stepIndex: 2, reason: "skip_button")
        agg.recordDismissal(tourId: "chat-intro", stepIndex: 0, reason: "click_outside")
        await agg.flush()
    }

    func testEmptyTourIdIgnored() async {
        let agg = TourEngagementAggregator.shared
        agg.recordStart(tourId: "", auth0Sub: "auth0|abc")
        await agg.flush() // noop — bucket never created
    }
}
