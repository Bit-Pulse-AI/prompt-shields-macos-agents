import Foundation
import os
import AppKit

// In-memory rollup of guided-tour interactions, keyed by
// (day, auth0Sub, tourId). Mirrors UsageEventAggregator's shape and
// piggybacks on its lifecycle hooks — flushes on the same triggers
// (sleep / quit / app-deactivate / 5-min heartbeat).
//
// Records on three signals (called from TourCoordinator):
//   - recordStart(tourId:)
//   - recordCompletion(tourId:, durationSec:)
//   - recordDismissal(tourId:, stepIndex:, reason:)
//
// Each bumps the relevant counter. We do NOT record every
// tourStepShown event — that'd inflate batches by N steps per tour
// and the dashboard's funnel chart can derive shown count from
// startCount when needed.

@MainActor
final class TourEngagementAggregator {
    static let shared = TourEngagementAggregator()

    private struct Bucket {
        var startCount: Int = 0
        var completionCount: Int = 0
        var dismissalCounts: [String: Int] = [:]
        var totalDurationSec: Double = 0
        var stepDismissalCounts: [String: Int] = [:]
        var firstSeen: Date = .now
        var lastSeen: Date = .now
    }

    private var buckets: [String: Bucket] = [:]   // key = "day|sub|tourId"
    private var flushTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "TourEngagementAggregator"
    )

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard flushTask == nil else { return }
        installObservers()
        // 5-minute heartbeat, same cadence as the usage aggregator.
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await self?.flush()
            }
        }
    }

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        let names: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (nc, NSApplication.willTerminateNotification),
            (nc, NSApplication.willResignActiveNotification)
        ]
        for (center, name) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.flush() }
            }
            observers.append(token)
        }
    }

    // MARK: - Recording

    func recordStart(tourId: String, auth0Sub: String? = nil) {
        bump(tourId: tourId, auth0Sub: auth0Sub) { $0.startCount += 1 }
    }

    func recordCompletion(tourId: String, durationSec: Double, auth0Sub: String? = nil) {
        bump(tourId: tourId, auth0Sub: auth0Sub) {
            $0.completionCount += 1
            $0.totalDurationSec += max(durationSec, 0)
        }
    }

    func recordDismissal(tourId: String, stepIndex: Int, reason: String, auth0Sub: String? = nil) {
        bump(tourId: tourId, auth0Sub: auth0Sub) {
            $0.dismissalCounts[reason, default: 0] += 1
            $0.stepDismissalCounts[String(stepIndex), default: 0] += 1
        }
    }

    private func bump(tourId: String, auth0Sub: String?, mutate: (inout Bucket) -> Void) {
        guard !tourId.isEmpty else { return }
        let day = Self.dayKey(for: .now)
        let key = "\(day)|\(auth0Sub ?? "anon")|\(tourId)"
        var bucket = buckets[key] ?? Bucket()
        mutate(&bucket)
        bucket.lastSeen = .now
        buckets[key] = bucket
    }

    // MARK: - Flush

    func flush() async {
        guard !buckets.isEmpty else { return }
        let snapshot = buckets
        buckets.removeAll()

        let iso = ISO8601DateFormatter()
        let events: [TourEngagementEvent] = snapshot.compactMap { (key, bucket) in
            let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let day = String(parts[0])
            let sub = String(parts[1])
            let tourId = String(parts[2])
            return TourEngagementEvent(
                day: day,
                auth0Sub: sub == "anon" ? nil : sub,
                tourId: tourId,
                startCount: bucket.startCount,
                completionCount: bucket.completionCount,
                dismissalCounts: bucket.dismissalCounts,
                totalDurationSec: bucket.totalDurationSec,
                stepDismissalCounts: bucket.stepDismissalCounts,
                firstSeen: iso.string(from: bucket.firstSeen),
                lastSeen: iso.string(from: bucket.lastSeen)
            )
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        await TelemetryClient.shared.flushTourEngagementBatch(
            TourEngagementBatch(events: events, appVersion: appVersion)
        )
    }

    // MARK: - Helpers

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .init(identifier: .iso8601)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
