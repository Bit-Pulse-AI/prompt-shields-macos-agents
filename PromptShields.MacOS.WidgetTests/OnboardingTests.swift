import XCTest
@testable import PromptShields_MacOS_Widget

/// Tests for the onboarding navigation primitives (PS-04/05/06).
final class OnboardingTests: XCTestCase {

    private let key = "ai.bit-pulse.promptshields.hasCompletedOnboarding"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    // MARK: - Step navigation

    func testStepsAreFourInOrder() {
        let steps = OnboardingStep.allCases
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps[0], .welcome)
        XCTAssertEqual(steps[1], .howItWorks)
        XCTAssertEqual(steps[2], .permission)
        XCTAssertEqual(steps[3], .ahaMoment)
    }

    func testForwardChain() {
        XCTAssertEqual(OnboardingStep.welcome.next, .howItWorks)
        XCTAssertEqual(OnboardingStep.howItWorks.next, .permission)
        XCTAssertEqual(OnboardingStep.permission.next, .ahaMoment)
        XCTAssertNil(OnboardingStep.ahaMoment.next, "Last step has no next")
    }

    func testBackwardChain() {
        XCTAssertNil(OnboardingStep.welcome.previous, "First step has no previous")
        XCTAssertEqual(OnboardingStep.howItWorks.previous, .welcome)
        XCTAssertEqual(OnboardingStep.ahaMoment.previous, .permission)
    }

    func testProgressScalesFromZeroToOne() {
        XCTAssertEqual(OnboardingStep.welcome.progress, 0.0, accuracy: 0.001)
        XCTAssertEqual(OnboardingStep.ahaMoment.progress, 1.0, accuracy: 0.001)
        XCTAssertGreaterThan(OnboardingStep.howItWorks.progress, 0.0)
        XCTAssertLessThan(OnboardingStep.howItWorks.progress, 1.0)
    }

    // MARK: - Persistence

    func testNotCompletedByDefault() {
        XCTAssertFalse(OnboardingPersistence.hasCompleted,
                       "Fresh install must show onboarding (PS-04 AC)")
    }

    func testMarkCompletedRoundTrips() {
        OnboardingPersistence.markCompleted()
        XCTAssertTrue(OnboardingPersistence.hasCompleted)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
    }

    func testResetReturnsToPristine() {
        OnboardingPersistence.markCompleted()
        XCTAssertTrue(OnboardingPersistence.hasCompleted)
        OnboardingPersistence.reset()
        XCTAssertFalse(OnboardingPersistence.hasCompleted,
                       "reset() must re-enable the first-launch sheet")
    }
}
