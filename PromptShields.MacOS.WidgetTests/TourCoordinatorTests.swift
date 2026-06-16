import XCTest
@testable import PromptShields_MacOS_Widget

/// Pins the tour-engine contract documented in §10 of
/// guided-tour-design.md — completion flags persist, manual triggers
/// bypass them, queued triggers fire after the active tour ends.
@MainActor
final class TourCoordinatorTests: XCTestCase {

    private let prefix = "ai.bit-pulse.promptly.tour."

    override func setUp() {
        super.setUp()
        TourCoordinator.shared.resetAllProgress()
    }

    override func tearDown() {
        TourCoordinator.shared.resetAllProgress()
        super.tearDown()
    }

    // MARK: - Catalog

    func testCatalogLoadsBundledTours() {
        let all = TourCatalog.allTours()
        XCTAssertGreaterThan(all.count, 0, "Tours.json must ship with the bundle")
        let ids = Set(all.map(\.id))
        XCTAssertTrue(ids.contains("dashboard-intro"))
        XCTAssertTrue(ids.contains("chat-intro"))
    }

    func testEverysStepHasAnchorAndCopy() {
        for tour in TourCatalog.allTours() {
            XCTAssertGreaterThan(tour.steps.count, 0, "\(tour.id) has no steps")
            for step in tour.steps {
                XCTAssertFalse(step.anchorId.isEmpty, "\(tour.id)/\(step.id) missing anchor")
                XCTAssertFalse(step.title.isEmpty)
                XCTAssertFalse(step.body.isEmpty)
            }
        }
    }

    func testTriggerFiltering() {
        let autoStarted = TourCatalog.tours(triggeredBy: .firstDashboardMount)
        XCTAssertTrue(autoStarted.contains { $0.id == "dashboard-intro" })
        let manualOnly = TourCatalog.tours(triggeredBy: .manual)
        XCTAssertTrue(manualOnly.contains { $0.id == "settings-intro" })
    }

    // MARK: - Lifecycle

    func testStartAdvancesAndCompletes() {
        let coord = TourCoordinator.shared
        coord.start("chat-intro")
        XCTAssertNotNil(coord.activeTour)
        XCTAssertEqual(coord.activeStepIndex, 0)

        let total = coord.activeTour!.steps.count
        for _ in 0..<total {
            coord.next()
        }
        XCTAssertNil(coord.activeTour, "Past the last step the tour should end")
        XCTAssertTrue(coord.hasCompleted("chat-intro"))
    }

    func testSkipMarksDismissed() {
        let coord = TourCoordinator.shared
        coord.start("activity-log-intro")
        coord.skip()
        XCTAssertNil(coord.activeTour)
        XCTAssertTrue(coord.hasDismissed("activity-log-intro"))
        XCTAssertFalse(coord.hasCompleted("activity-log-intro"),
                       "Skip dismisses, doesn't count as complete")
    }

    func testAutoStartHonoursCompletion() {
        let coord = TourCoordinator.shared
        coord.start("dashboard-intro")
        for _ in 0..<coord.activeTour!.steps.count { coord.next() }
        XCTAssertTrue(coord.hasCompleted("dashboard-intro"))

        // Second auto-trigger should be a noop.
        coord.autoStart(trigger: .firstDashboardMount)
        XCTAssertNil(coord.activeTour, "Completed tour should not auto-fire again")
    }

    func testManualStartBypassesCompletion() {
        let coord = TourCoordinator.shared
        coord.start("dashboard-intro")
        for _ in 0..<coord.activeTour!.steps.count { coord.next() }

        coord.start("dashboard-intro")
        XCTAssertNotNil(coord.activeTour, "Manual start should bypass the completion flag")
        XCTAssertEqual(coord.activeStepIndex, 0)
    }

    func testDisableAllShortCircuits() {
        UserDefaults.standard.set(true, forKey: prefix + "disableAll")
        defer { UserDefaults.standard.removeObject(forKey: prefix + "disableAll") }
        TourCoordinator.shared.autoStart(trigger: .firstDashboardMount)
        XCTAssertNil(TourCoordinator.shared.activeTour)
    }

    // MARK: - Interaction-allowed steps (Q1)

    func testUserPerformedAnchorActionAdvancesWhenAllowed() {
        let coord = TourCoordinator.shared
        coord.start("dashboard-intro")
        // Step 0 has interactionAllowed: false → no advance
        let beforeIndex = coord.activeStepIndex
        coord.userPerformedAnchorAction()
        XCTAssertEqual(coord.activeStepIndex, beforeIndex,
                       "Step without interactionAllowed must not advance on anchor action")
        // Step 1 (activate-button) has interactionAllowed: true
        coord.next()
        let step1Index = coord.activeStepIndex
        coord.userPerformedAnchorAction()
        XCTAssertEqual(coord.activeStepIndex, step1Index + 1,
                       "Step with interactionAllowed should advance on anchor action")
    }

    // MARK: - Persistence keys (Q3, design doc §5)

    func testCompletedKeyFormat() {
        let coord = TourCoordinator.shared
        coord.start("chat-intro")
        for _ in 0..<coord.activeTour!.steps.count { coord.next() }
        let key = prefix + "chat-intro.completedAt"
        XCTAssertNotNil(UserDefaults.standard.string(forKey: key),
                        "Completion key must use the documented format")
    }
}
