import Foundation
import os

// Bundled allowlist of apps where Promptly monitors prompts (PS-13).
// Rationale: the AI surface area grows quickly — keeping a plist alongside
// the binary lets us add new tools without a code release. Per-app disable
// state is persisted per-user in UserDefaults.

struct MonitoredApp: Sendable, Identifiable, Hashable {
    enum Category: String, Sendable {
        case native      // bundleId match only
        case web         // web host match only (inside a browser)
        case mixed       // both paths

        init(raw: String) {
            self = Category(rawValue: raw) ?? .mixed
        }
    }

    let id: String
    let name: String
    let category: Category
    let bundleIds: Set<String>
    let webHosts: [String]

    func matches(bundleId: String) -> Bool {
        guard !bundleId.isEmpty else { return false }
        return bundleIds.contains(bundleId)
    }

    func matches(urlHost: String) -> Bool {
        let lowered = urlHost.lowercased()
        return webHosts.contains { lowered.contains($0) }
    }
}

final class MonitoredAppsRegistry: @unchecked Sendable {
    static let shared = MonitoredAppsRegistry()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "MonitoredAppsRegistry"
    )

    private(set) var apps: [MonitoredApp] = []
    private(set) var browserBundleIds: Set<String> = []

    private let disabledKey = "ai.bit-pulse.promptshields.disabledMonitoredApps"
    private let queue = DispatchQueue(label: "monitoredapps.registry", attributes: .concurrent)

    private init() {
        load()
    }

    // MARK: - Loading

    private func load() {
        guard let url = Bundle.main.url(forResource: "MonitoredApps", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            logger.error("MonitoredApps.plist missing or malformed — monitoring will fall back to browser-only")
            browserBundleIds = MonitoredAppsRegistry.fallbackBrowsers
            return
        }

        if let browsers = plist["browsers"] as? [String] {
            browserBundleIds = Set(browsers)
        } else {
            browserBundleIds = MonitoredAppsRegistry.fallbackBrowsers
        }

        if let rawApps = plist["apps"] as? [[String: Any]] {
            apps = rawApps.compactMap(MonitoredAppsRegistry.parse)
        }

        logger.debug("Loaded \(self.apps.count) monitored apps, \(self.browserBundleIds.count) browsers")
    }

    private static func parse(_ entry: [String: Any]) -> MonitoredApp? {
        guard let id = entry["id"] as? String,
              let name = entry["name"] as? String else {
            return nil
        }
        let category = MonitoredApp.Category(raw: entry["category"] as? String ?? "mixed")
        let bundleIds = Set((entry["bundleIds"] as? [String]) ?? [])
        let hosts = (entry["webHosts"] as? [String])?.map { $0.lowercased() } ?? []
        return MonitoredApp(id: id, name: name, category: category, bundleIds: bundleIds, webHosts: hosts)
    }

    // MARK: - Per-user disabled state

    func isEnabled(_ app: MonitoredApp) -> Bool {
        !disabledIds.contains(app.id)
    }

    func setEnabled(_ app: MonitoredApp, enabled: Bool) {
        var current = disabledIds
        if enabled {
            current.remove(app.id)
        } else {
            current.insert(app.id)
        }
        UserDefaults.standard.set(Array(current), forKey: disabledKey)
    }

    private var disabledIds: Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: disabledKey) ?? []
        return Set(raw)
    }

    // MARK: - Query helpers

    /// True when the given browser bundleId is in our browser allowlist.
    func isBrowser(bundleId: String) -> Bool {
        browserBundleIds.contains(bundleId)
    }

    /// Returns the monitored-app record matching a native bundleId (if any,
    /// and enabled).
    func enabledNativeApp(bundleId: String) -> MonitoredApp? {
        guard !bundleId.isEmpty else { return nil }
        return apps.first { app in
            [.native, .mixed].contains(app.category)
                && app.matches(bundleId: bundleId)
                && isEnabled(app)
        }
    }

    /// True when the user has explicitly disabled the MonitoredApp record
    /// whose bundleId matches. Only returns true when we have a known record
    /// for this bundleId — unknown apps and browsers keep their default
    /// behavior (not blocked here; user-configured gating is per-app only).
    func isDisabled(bundleId: String) -> Bool {
        guard !bundleId.isEmpty else { return false }
        guard let app = apps.first(where: { $0.matches(bundleId: bundleId) }) else {
            return false
        }
        return !isEnabled(app)
    }

    /// Returns the monitored-app record matching a URL host (if any, and
    /// enabled). `host` may be the full URL string — we scan for substring
    /// host matches, which tolerates missing schemes.
    func enabledWebApp(urlString: String) -> MonitoredApp? {
        guard !urlString.isEmpty else { return nil }
        return apps.first { app in
            [.web, .mixed].contains(app.category)
                && app.matches(urlHost: urlString)
                && isEnabled(app)
        }
    }

    private static let fallbackBrowsers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "org.mozilla.firefox"
    ]
}
