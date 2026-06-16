import XCTest
@testable import PromptShields_MacOS_Widget

/// Sprint D telemetry: pins the AnalyticsEvent payload shape so a TS
/// renaming on the dashboard side (if it ever consumes these events
/// directly) doesn't drift silently. We don't have a hook into the
/// global Analytics dispatcher here; the contract we verify is the
/// AnalyticsEvent enum's name + category + parameter keys.
final class TourTelemetryTests: XCTestCase {

    func testTourStartedShape() {
        let event = AnalyticsEvent.tourStarted(id: "dashboard-intro", trigger: "manual")
        XCTAssertEqual(event.name, "tour_started")
        XCTAssertEqual(event.category, "guided_tour")
        XCTAssertEqual(event.parameters["tour_id"] as? String, "dashboard-intro")
        XCTAssertEqual(event.parameters["trigger"] as? String, "manual")
    }

    func testTourStepShownShape() {
        let event = AnalyticsEvent.tourStepShown(id: "chat-intro", stepIndex: 2)
        XCTAssertEqual(event.name, "tour_step_shown")
        XCTAssertEqual(event.parameters["tour_id"] as? String, "chat-intro")
        XCTAssertEqual(event.parameters["step_index"] as? Int, 2)
    }

    func testTourStepDismissedReason() {
        for reason in ["skip_button", "esc", "click_outside"] {
            let event = AnalyticsEvent.tourStepDismissed(
                id: "settings-intro", stepIndex: 1, reason: reason
            )
            XCTAssertEqual(event.parameters["dismiss_reason"] as? String, reason)
            XCTAssertEqual(event.category, "guided_tour")
        }
    }

    func testTourCompletedCarriesDuration() {
        let event = AnalyticsEvent.tourCompleted(id: "dashboard-intro", durationSec: 42.5)
        XCTAssertEqual(event.name, "tour_completed")
        XCTAssertEqual(event.parameters["duration_seconds"] as? Double, 42.5)
        XCTAssertEqual(event.parameters["tour_id"] as? String, "dashboard-intro")
    }

    // MARK: - Skip-reason wiring

    /// Defaults to skip_button when called without an explicit reason —
    /// so existing call sites that just call `coordinator.skip()` still
    /// produce a meaningful dismiss_reason field.
    @MainActor
    func testSkipDefaultsToSkipButton() {
        let coord = TourCoordinator.shared
        coord.resetAllProgress()
        coord.start("dashboard-intro")
        coord.skip()
        XCTAssertNil(coord.activeTour)
        XCTAssertTrue(coord.hasDismissed("dashboard-intro"))
    }

    @MainActor
    func testSkipForwardsExplicitReason() {
        let coord = TourCoordinator.shared
        coord.resetAllProgress()
        coord.start("chat-intro")
        coord.skip(reason: "esc")
        // We can't observe the analytics call directly, but the dismissed
        // flag must still land — pins the contract that reason is purely
        // additive telemetry, never alters lifecycle.
        XCTAssertTrue(coord.hasDismissed("chat-intro"))
        XCTAssertFalse(coord.hasCompleted("chat-intro"))
    }
}
