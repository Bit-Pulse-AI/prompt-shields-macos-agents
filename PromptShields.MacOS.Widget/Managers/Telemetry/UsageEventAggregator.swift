import Foundation
import os
import AppKit

// In-memory aggregator that rolls per-event counters into a single
// UsageEvent per (day, auth0Sub, promptlyAppId) tuple. The dashboard
// only needs daily granularity for the adoption + ticket-deflection
// metrics, and shipping every keystroke would be a privacy + cost
// problem we don't want.
//
// Lifecycle:
//   - record() bumps an in-memory counter
//   - flushIfDue() pushes the rolled-up batch via TelemetryClient
//   - we flush on:
//       * NSWorkspace.didDeactivateApplication (Promptly resigns active)
//       * willSleep / screensDidSleep
//       * applicationWillTerminate
//       * a 5-minute periodic timer as a safety net
//
// Persistence: in-memory only for now. If a user closes the lid before
// flush, the batch is lost. Acceptable for v1; revisit if numbers matter.

@MainActor
final class UsageEventAggregator {
    static let shared = UsageEventAggregator()

    private struct Bucket {
        var promptCount: Int = 0
        var blockedCount: Int = 0
        var redactedCount: Int = 0
        var flaggedCount: Int = 0
        var firstSeen: Date = .now
        var lastSeen: Date = .now
    }

    private var buckets: [String: Bucket] = [:]   // key = "day|sub|appId"
    private var flushTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "UsageEventAggregator"
    )

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard flushTask == nil else { return }
        installObservers()
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
                Task { @MainActor [weak self] in
                    await self?.flush()
                }
            }
            observers.append(token)
        }
    }

    // MARK: - Recording

    /// Bumps the relevant counter for an event. `kind` maps to the
    /// per-action counters on UsageEvent.
    enum Kind: Sendable {
        case prompt          // any user-driven action (suggestion accept, chat send, clean evaluation)
        case blocked
        case redacted
        case flagged
    }

    func record(kind: Kind, promptlyAppId: String, auth0Sub: String?) {
        guard !promptlyAppId.isEmpty else { return }
        let day = Self.dayKey(for: .now)
        let key = "\(day)|\(auth0Sub ?? "anon")|\(promptlyAppId)"
        var bucket = buckets[key] ?? Bucket()
        switch kind {
        case .prompt: bucket.promptCount += 1
        case .blocked: bucket.blockedCount += 1
        case .redacted: bucket.redactedCount += 1
        case .flagged: bucket.flaggedCount += 1
        }
        bucket.lastSeen = .now
        buckets[key] = bucket
    }

    // MARK: - Flush

    func flush() async {
        guard !buckets.isEmpty else { return }
        let snapshot = buckets
        buckets.removeAll()

        let isoFormatter = ISO8601DateFormatter()
        let events: [UsageEvent] = snapshot.compactMap { (key, bucket) in
            let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let day = String(parts[0])
            let sub = String(parts[1])
            let appId = String(parts[2])
            return UsageEvent(
                day: day,
                auth0Sub: sub == "anon" ? nil : sub,
                promptlyAppId: appId,
                promptCount: bucket.promptCount,
                blockedCount: bucket.blockedCount,
                redactedCount: bucket.redactedCount,
                flaggedCount: bucket.flaggedCount,
                firstSeen: isoFormatter.string(from: bucket.firstSeen),
                lastSeen: isoFormatter.string(from: bucket.lastSeen)
            )
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        await TelemetryClient.shared.flushUsageBatch(
            UsageEventBatch(events: events, appVersion: appVersion)
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
