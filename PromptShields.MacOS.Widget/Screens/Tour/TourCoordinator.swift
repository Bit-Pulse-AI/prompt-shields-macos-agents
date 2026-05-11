import Foundation
import os
import SwiftUI

// Singleton owner of the active tour, step index, and completion
// persistence. Views observe `activeTour` + `activeStepIndex` and react
// — Q3 in the design doc: only one tour at a time, others queue and
// skip if the trigger window passes.
//
// Decisions confirmed in §10 of guided-tour-design.md:
//   Q1 — interaction during step:  yes, with auto-advance on action
//   Q2 — first-launch timing:      1.2s breather after dashboard mounts
//   Q3 — multi-tour orchestration: one tour active, others queue + skip
//   Q4 — dark-mode theming:        bake in from day one
//   Q5 — cross-window step UX:     dashboard shows arrow, chat stays unspotlighted
//   Q6 — admin authoring:          eventual, bundled JSON for v1

@MainActor
final class TourCoordinator: ObservableObject {
    static let shared = TourCoordinator()

    @Published private(set) var activeTour: Tour?
    @Published private(set) var activeStepIndex: Int = 0

    /// In-flight trigger requests that arrived while another tour was
    /// already running. We pop them when the current tour ends, but only
    /// if the trigger window is still "first time" — see allowTrigger.
    private var queuedTriggers: [TourTrigger] = []

    /// Timestamp of the active tour's start, for the tourCompleted
    /// duration field. Set in present(), cleared in endActive().
    private var activeStartedAt: Date?
    /// Reason recorded when the user skips — distinguishes between
    /// "esc / click outside / button" without needing a separate
    /// public skip(reason:) API. Reset on every step transition.
    private var pendingDismissReason: String = "skip_button"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "TourCoordinator"
    )

    private static let completedSuffix = ".completedAt"
    private static let dismissedSuffix = ".dismissedAt"
    private static let disableAllKey = "ai.bit-pulse.promptly.tour.disableAll"
    private static let keyPrefix = "ai.bit-pulse.promptly.tour."

    var activeStep: TourStep? {
        guard let activeTour, activeTour.steps.indices.contains(activeStepIndex) else { return nil }
        return activeTour.steps[activeStepIndex]
    }

    var isActive: Bool { activeTour != nil }

    // MARK: - Public API

    /// Manually start a tour (e.g. from the Help menu). Bypasses
    /// completion / dismissal flags. Cancels whatever's currently up.
    func start(_ tourId: String) {
        guard let tour = TourCatalog.tour(id: tourId) else {
            logger.error("Unknown tour id: \(tourId, privacy: .public)")
            return
        }
        present(tour, source: "manual")
    }

    /// Called by .tourAutoStart modifiers. Honours completion flags +
    /// the global disable switch + the single-tour rule.
    func autoStart(trigger: TourTrigger) {
        guard !UserDefaults.standard.bool(forKey: Self.disableAllKey) else { return }

        // Single-tour rule: if a tour is currently running, queue the
        // trigger and we'll consider it when the current one completes.
        if isActive {
            queuedTriggers.append(trigger)
            return
        }

        // Find the (first) tour matching this trigger that the user
        // hasn't completed or explicitly dismissed.
        let candidates = TourCatalog.tours(triggeredBy: trigger)
        for tour in candidates where !hasCompleted(tour.id) && !hasDismissed(tour.id) {
            present(tour, source: trigger.rawValue)
            return
        }
    }

    func next() {
        guard let activeTour else { return }
        let nextIndex = activeStepIndex + 1
        if nextIndex >= activeTour.steps.count {
            complete()
        } else {
            activeStepIndex = nextIndex
            broadcastStep()
        }
    }

    func skip(reason: String = "skip_button") {
        guard let tour = activeTour else { return }
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: .now),
                                  forKey: Self.keyPrefix + tour.id + Self.dismissedSuffix)
        Analytics.trackAsync(.tourStepDismissed(
            id: tour.id,
            stepIndex: activeStepIndex,
            reason: reason
        ))
        TourEngagementAggregator.shared.recordDismissal(
            tourId: tour.id,
            stepIndex: activeStepIndex,
            reason: reason
        )
        endActive()
    }

    /// Called externally (e.g. from the highlighted button's tap handler)
    /// when the user performs the action the spotlight expects. Behaves
    /// the same as `next()` if the active step has interactionAllowed.
    func userPerformedAnchorAction() {
        guard let step = activeStep, step.resolvedInteractionAllowed else { return }
        next()
    }

    /// Reset all completion flags. Used by the Help menu's "Replay all
    /// tours" item and by QA. Doesn't touch the disableAll kill-switch.
    func resetAllProgress() {
        let defaults = UserDefaults.standard
        for tour in TourCatalog.allTours() {
            defaults.removeObject(forKey: Self.keyPrefix + tour.id + Self.completedSuffix)
            defaults.removeObject(forKey: Self.keyPrefix + tour.id + Self.dismissedSuffix)
        }
    }

    // MARK: - State queries

    func hasCompleted(_ tourId: String) -> Bool {
        UserDefaults.standard.string(forKey: Self.keyPrefix + tourId + Self.completedSuffix) != nil
    }

    func hasDismissed(_ tourId: String) -> Bool {
        UserDefaults.standard.string(forKey: Self.keyPrefix + tourId + Self.dismissedSuffix) != nil
    }

    // MARK: - Private

    private func present(_ tour: Tour, source: String) {
        logger.debug("Presenting tour \(tour.id, privacy: .public) (source=\(source, privacy: .public))")
        activeTour = tour
        activeStepIndex = 0
        activeStartedAt = .now
        pendingDismissReason = "skip_button"
        Analytics.trackAsync(.tourStarted(id: tour.id, trigger: source))
        TourEngagementAggregator.shared.recordStart(tourId: tour.id)
        broadcastStep()
    }

    private func complete() {
        guard let tour = activeTour else { return }
        let duration: Double = {
            guard let start = activeStartedAt else { return 0 }
            return Date().timeIntervalSince(start)
        }()
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: .now),
                                  forKey: Self.keyPrefix + tour.id + Self.completedSuffix)
        Analytics.trackAsync(.tourCompleted(id: tour.id, durationSec: duration))
        TourEngagementAggregator.shared.recordCompletion(tourId: tour.id, durationSec: duration)
        endActive()
    }

    private func endActive() {
        activeTour = nil
        activeStepIndex = 0
        activeStartedAt = nil
        NotificationCenter.default.post(name: .tourActiveStep, object: nil, userInfo: [
            "tourId": "",
            "stepId": ""
        ])
        // Drain the queue. We honour at most one queued trigger to avoid
        // chaining 4 tours back-to-back.
        if let next = queuedTriggers.first {
            queuedTriggers.removeAll()
            autoStart(trigger: next)
        }
    }

    private func broadcastStep() {
        guard let tour = activeTour, let step = activeStep else { return }
        Analytics.trackAsync(.tourStepShown(id: tour.id, stepIndex: activeStepIndex))
        NotificationCenter.default.post(name: .tourActiveStep, object: nil, userInfo: [
            "tourId": tour.id,
            "stepId": step.id,
            "anchorId": step.anchorId,
            "stepIndex": activeStepIndex,
            "stepCount": tour.steps.count
        ])
    }
}

extension Notification.Name {
    /// Posted by TourCoordinator whenever the active step changes. Cross-
    /// window listeners (the chat panel today, future tutorial overlay
    /// later) subscribe to know when to render their own coachmark for
    /// an anchor they own.
    static let tourActiveStep = Notification.Name("ai.bit-pulse.promptly.tour.activeStep")
}
