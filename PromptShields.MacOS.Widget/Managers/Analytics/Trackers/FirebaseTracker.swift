import Foundation
import os

// MARK: - Firebase Tracker

/// Firebase tracker for performance monitoring and crash reporting
/// Uses Firebase REST APIs for macOS compatibility
/// Focus: Performance metrics, crash reports, and critical errors
actor FirebaseTracker: AnalyticsTracker {
    // MARK: - Properties

    nonisolated let identifier = TrackerType.firebase.rawValue

    private var _isEnabled: Bool = true
    nonisolated var isEnabled: Bool { true }

    private let apiKey: String
    private let projectId: String
    private let appId: String
    private let installationId: String
    private var userProperties: AnalyticsUserProperties?
    private var activeTraces: [String: PerformanceTrace] = [:]
    private var crashQueue: [CrashReport] = []

    private let configuration: AnalyticsConfiguration
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "Firebase"
    )

    // MARK: - Types

    /// Represents a performance trace
    private struct PerformanceTrace: Sendable {
        let name: String
        let startTime: Date
        var attributes: [String: String]
        var counters: [String: Int]
    }

    /// Represents a crash report
    private struct CrashReport: Sendable {
        let timestamp: Date
        let reason: String
        let stackTrace: String
        let userInfo: [String: String]
        let appState: AppState
    }

    /// Application state at time of crash
    private struct AppState: Sendable {
        let appVersion: String
        let buildNumber: String
        let osVersion: String
        let memoryUsage: UInt64
        let diskUsage: UInt64
    }

    /// Firebase Performance Event payload
    private struct PerformancePayload: Codable {
        let appId: String
        let appVersion: String
        let osVersion: String
        let deviceModel: String
        let traces: [TracePayload]

        enum CodingKeys: String, CodingKey {
            case appId = "app_id"
            case appVersion = "app_version"
            case osVersion = "os_version"
            case deviceModel = "device_model"
            case traces
        }
    }

    private struct TracePayload: Codable {
        let name: String
        let startTime: Int64
        let duration: Int64
        let attributes: [String: String]
        let counters: [String: Int]

        enum CodingKeys: String, CodingKey {
            case name
            case startTime = "start_time"
            case duration
            case attributes
            case counters
        }
    }

    /// Crashlytics payload structure
    private struct CrashlyticsPayload: Codable {
        let appId: String
        let installationId: String
        let timestamp: String
        let reason: String
        let stackTrace: String
        let appVersion: String
        let buildNumber: String
        let osVersion: String
        let memoryUsage: UInt64
        let diskUsage: UInt64
        let customKeys: [String: String]

        enum CodingKeys: String, CodingKey {
            case appId = "app_id"
            case installationId = "installation_id"
            case timestamp
            case reason
            case stackTrace = "stack_trace"
            case appVersion = "app_version"
            case buildNumber = "build_number"
            case osVersion = "os_version"
            case memoryUsage = "memory_usage"
            case diskUsage = "disk_usage"
            case customKeys = "custom_keys"
        }
    }

    // MARK: - Initialization

    init(
        apiKey: String,
        projectId: String,
        appId: String,
        configuration: AnalyticsConfiguration = .default
    ) {
        self.apiKey = apiKey
        self.projectId = projectId
        self.appId = appId
        self.configuration = configuration

        // Generate or retrieve persistent installation ID
        if let storedId = UserDefaults.standard.string(forKey: "firebase_installation_id") {
            self.installationId = storedId
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: "firebase_installation_id")
            self.installationId = newId
        }

        self._isEnabled = configuration.isEnabled
    }

    // MARK: - AnalyticsTracker

    func initialize() async {
        logger.info("Firebase tracker initialized")
        logger.info("Project ID: \(self.projectId)")
        logger.info("Installation ID: \(self.installationId)")

        // Setup crash handler
        setupCrashHandler()

        // Send any pending crash reports from previous session
        await sendPendingCrashReports()
    }

    func track(_ event: AnalyticsEvent) async {
        guard _isEnabled else {
            logger.debug("Tracker disabled, skipping event: \(event.name)")
            return
        }

        guard !apiKey.isEmpty else {
            logger.debug("Firebase API key not configured, skipping event: \(event.name)")
            return
        }

        // Firebase tracker focuses on performance and errors
        switch event {
        case .performanceMetric(let name, let value, let unit):
            await trackPerformanceMetric(name: name, value: value, unit: unit)

        case .errorOccurred(let domain, let code, let message):
            await trackNonFatalError(domain: domain, code: code, message: message)

        case .crashDetected(let reason):
            await recordCrash(reason: reason)

        case .suggestionProcessingStarted(let type):
            startTrace(name: "suggestion_\(type)")

        case .suggestionProcessingCompleted(let type, let duration):
            endTrace(name: "suggestion_\(type)", duration: duration)

        case .suggestionProcessingFailed(let type, let error):
            endTrace(name: "suggestion_\(type)", error: error)

        case .textInjectionStarted(let app):
            startTrace(name: "text_injection_\(app)")

        case .textInjectionSucceeded(let app, _):
            endTrace(name: "text_injection_\(app)")

        case .textInjectionFailed(let app, let error):
            endTrace(name: "text_injection_\(app)", error: error)

        case .appLaunched:
            startTrace(name: "app_startup")

        default:
            // Other events are handled by other trackers
            break
        }
    }

    func setUserProperties(_ properties: AnalyticsUserProperties) async {
        self.userProperties = properties
        logger.debug("User properties updated")
    }

    func reset() async {
        activeTraces.removeAll()
        crashQueue.removeAll()
        userProperties = nil
        logger.info("Firebase tracker reset")
    }

    func flush() async {
        // Send any completed traces
        await sendCompletedTraces()
        // Send any pending crash reports
        await sendPendingCrashReports()
    }

    func setEnabled(_ enabled: Bool) async {
        _isEnabled = enabled
        logger.info("Firebase tracker \(enabled ? "enabled" : "disabled")")
    }

    // MARK: - Performance Tracing

    /// Start a performance trace
    func startTrace(name: String, attributes: [String: String] = [:]) {
        let trace = PerformanceTrace(
            name: name,
            startTime: Date(),
            attributes: attributes,
            counters: [:]
        )
        activeTraces[name] = trace
        logger.debug("Started trace: \(name)")
    }

    /// End a performance trace and record it
    func endTrace(name: String, duration: TimeInterval? = nil, error: String? = nil) {
        guard var trace = activeTraces.removeValue(forKey: name) else {
            logger.warning("Trace not found: \(name)")
            return
        }

        if let error = error {
            trace.attributes["error"] = error
        }

        let actualDuration = duration ?? Date().timeIntervalSince(trace.startTime)

        Task {
            await recordTrace(trace, duration: actualDuration)
        }
    }

    /// Increment a counter in an active trace
    func incrementCounter(traceName: String, counterName: String, by value: Int = 1) {
        guard var trace = activeTraces[traceName] else { return }
        trace.counters[counterName, default: 0] += value
        activeTraces[traceName] = trace
    }

    /// Add attribute to an active trace
    func addAttribute(traceName: String, key: String, value: String) {
        guard var trace = activeTraces[traceName] else { return }
        trace.attributes[key] = value
        activeTraces[traceName] = trace
    }

    // MARK: - Performance Metrics

    private func trackPerformanceMetric(name: String, value: Double, unit: String) async {
        guard !apiKey.isEmpty else { return }

        let trace = PerformanceTrace(
            name: name,
            startTime: Date(),
            attributes: ["unit": unit, "value": String(value)],
            counters: [:]
        )

        await recordTrace(trace, duration: value)
    }

    private func recordTrace(_ trace: PerformanceTrace, duration: TimeInterval) async {
        guard !apiKey.isEmpty else { return }

        let tracePayload = TracePayload(
            name: trace.name,
            startTime: Int64(trace.startTime.timeIntervalSince1970 * 1000),
            duration: Int64(duration * 1000), // Convert to milliseconds
            attributes: trace.attributes,
            counters: trace.counters
        )

        let payload = PerformancePayload(
            appId: appId,
            appVersion: version,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: "Mac",
            traces: [tracePayload]
        )

        await sendPerformancePayload(payload)
    }

    private func sendPerformancePayload(_ payload: PerformancePayload) async {
        // Firebase Performance Monitoring REST endpoint
        // Note: In production, you'd use the Firebase SDK or a server-side relay
        let urlString = "https://firebaselogging.googleapis.com/v0/performance/\(projectId)"

        guard let url = URL(string: urlString) else {
            logger.error("Invalid Firebase Performance URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(payload)

            if configuration.isDebugMode {
                logger.debug("Recording performance trace: \(payload.traces.first?.name ?? "unknown")")
            }

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 204 {
                    logger.debug("Performance trace recorded successfully")
                } else {
                    logger.warning("Firebase Performance returned status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            logger.error("Failed to send performance data: \(error.localizedDescription)")
        }
    }

    private func sendCompletedTraces() async {
        // This would batch send any remaining traces
        // For now, traces are sent immediately upon completion
    }

    // MARK: - Crash Reporting

    private func setupCrashHandler() {
        // Setup signal handlers for crash detection
        // Note: For production, consider using a dedicated crash reporting library

        // Store app state for crash reports
        saveCurrentAppState()
    }

    private func saveCurrentAppState() {
        let state: [String: Any] = [
            "appVersion": version,
            "buildNumber": build,
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        UserDefaults.standard.set(state, forKey: "firebase_last_app_state")
    }

    /// Record a crash that was detected
    private func recordCrash(reason: String) async {
        let appState = getCurrentAppState()
        var userInfo: [String: String] = [:]

        if let props = userProperties {
            if let userId = props.userId {
                userInfo["user_id"] = userId
            }
            if let tier = props.subscriptionTier {
                userInfo["subscription_tier"] = tier
            }
        }

        let crash = CrashReport(
            timestamp: Date(),
            reason: reason,
            stackTrace: Thread.callStackSymbols.joined(separator: "\n"),
            userInfo: userInfo,
            appState: appState
        )

        crashQueue.append(crash)

        // Persist crash for next session
        saveCrashReport(crash)

        // Try to send immediately
        await sendCrashReport(crash)
    }

    /// Track non-fatal errors
    private func trackNonFatalError(domain: String, code: String, message: String) async {
        guard !apiKey.isEmpty else { return }

        let appState = getCurrentAppState()

        var customKeys: [String: String] = [
            "error_domain": domain,
            "error_code": code
        ]

        if let props = userProperties {
            if let userId = props.userId {
                customKeys["user_id"] = userId
            }
        }

        let payload = CrashlyticsPayload(
            appId: appId,
            installationId: installationId,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            reason: message,
            stackTrace: Thread.callStackSymbols.joined(separator: "\n"),
            appVersion: appState.appVersion,
            buildNumber: appState.buildNumber,
            osVersion: appState.osVersion,
            memoryUsage: appState.memoryUsage,
            diskUsage: appState.diskUsage,
            customKeys: customKeys
        )

        await sendCrashlyticsPayload(payload, isFatal: false)
    }

    private func getCurrentAppState() -> AppState {
        AppState(
            appVersion: version,
            buildNumber: build,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            memoryUsage: getMemoryUsage(),
            diskUsage: getDiskUsage()
        )
    }

    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private func getDiskUsage() -> UInt64 {
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = attributes[.systemFreeSize] as? UInt64 {
            return freeSpace
        }
        return 0
    }

    private func saveCrashReport(_ crash: CrashReport) {
        // Serialize and save to UserDefaults for recovery on next launch
        let data: [String: Any] = [
            "timestamp": crash.timestamp.timeIntervalSince1970,
            "reason": crash.reason,
            "stackTrace": crash.stackTrace,
            "userInfo": crash.userInfo
        ]

        var pending = UserDefaults.standard.array(forKey: "firebase_pending_crashes") as? [[String: Any]] ?? []
        pending.append(data)
        UserDefaults.standard.set(pending, forKey: "firebase_pending_crashes")
    }

    private func sendPendingCrashReports() async {
        guard let pending = UserDefaults.standard.array(forKey: "firebase_pending_crashes") as? [[String: Any]] else {
            return
        }

        for crashData in pending {
            guard let timestamp = crashData["timestamp"] as? TimeInterval,
                  let reason = crashData["reason"] as? String,
                  let stackTrace = crashData["stackTrace"] as? String else {
                continue
            }

            let userInfo = crashData["userInfo"] as? [String: String] ?? [:]
            let appState = getCurrentAppState()

            let crash = CrashReport(
                timestamp: Date(timeIntervalSince1970: timestamp),
                reason: reason,
                stackTrace: stackTrace,
                userInfo: userInfo,
                appState: appState
            )

            await sendCrashReport(crash)
        }

        // Clear pending crashes
        UserDefaults.standard.removeObject(forKey: "firebase_pending_crashes")
    }

    private func sendCrashReport(_ crash: CrashReport) async {
        guard !apiKey.isEmpty else { return }

        let payload = CrashlyticsPayload(
            appId: appId,
            installationId: installationId,
            timestamp: ISO8601DateFormatter().string(from: crash.timestamp),
            reason: crash.reason,
            stackTrace: crash.stackTrace,
            appVersion: crash.appState.appVersion,
            buildNumber: crash.appState.buildNumber,
            osVersion: crash.appState.osVersion,
            memoryUsage: crash.appState.memoryUsage,
            diskUsage: crash.appState.diskUsage,
            customKeys: crash.userInfo
        )

        await sendCrashlyticsPayload(payload, isFatal: true)
    }

    private func sendCrashlyticsPayload(_ payload: CrashlyticsPayload, isFatal: Bool) async {
        // Firebase Crashlytics REST endpoint
        // Note: In production, you'd typically use a server-side relay or the official SDK
        let urlString = "https://firebasecrashlytics.googleapis.com/v0/\(projectId)/\(isFatal ? "crashes" : "errors")"

        guard let url = URL(string: urlString) else {
            logger.error("Invalid Crashlytics URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(payload)

            if configuration.isDebugMode {
                logger.debug("Sending \(isFatal ? "crash" : "error") report: \(payload.reason)")
            }

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 204 {
                    logger.info("\(isFatal ? "Crash" : "Error") report sent successfully")
                } else {
                    logger.warning("Crashlytics returned status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            logger.error("Failed to send \(isFatal ? "crash" : "error") report: \(error.localizedDescription)")
        }
    }
}

// MARK: - Factory

extension FirebaseTracker {
    /// Creates a Firebase tracker with configuration from constants
    static func createDefault() -> FirebaseTracker {
        #if DEBUG
        return FirebaseTracker(
            apiKey: firebaseApiKey,
            projectId: firebaseProjectId,
            appId: firebaseAppId,
            configuration: .debug
        )
        #else
        return FirebaseTracker(
            apiKey: firebaseApiKey,
            projectId: firebaseProjectId,
            appId: firebaseAppId,
            configuration: .default
        )
        #endif
    }
}

// MARK: - Performance Measurement Helpers

extension FirebaseTracker {
    /// Measure the duration of an async operation
    func measureAsync<T>(name: String, operation: () async throws -> T) async rethrows -> T {
        startTrace(name: name)
        do {
            let result = try await operation()
            endTrace(name: name)
            return result
        } catch {
            endTrace(name: name, error: error.localizedDescription)
            throw error
        }
    }

    /// Measure a synchronous operation
    func measure<T>(name: String, operation: () throws -> T) rethrows -> T {
        startTrace(name: name)
        do {
            let result = try operation()
            endTrace(name: name)
            return result
        } catch {
            endTrace(name: name, error: error.localizedDescription)
            throw error
        }
    }
}

