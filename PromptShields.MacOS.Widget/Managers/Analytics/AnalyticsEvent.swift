import Foundation

// MARK: - Analytics Event

/// Represents all trackable events in the application
/// Each event has a name, category, and optional parameters
enum AnalyticsEvent: Sendable {
    // MARK: - App Lifecycle Events
    case appLaunched
    case appTerminated
    case appBecameActive
    case appResignedActive

    // MARK: - Authentication Events
    case loginStarted
    case loginSucceeded(provider: String)
    case loginFailed(error: String)
    case logoutStarted
    case logoutCompleted
    case tokenRefreshed
    case tokenRefreshFailed(error: String)

    // MARK: - Accessibility Events
    case accessibilityPermissionRequested
    case accessibilityPermissionGranted
    case accessibilityPermissionDenied
    case monitoringEnabled
    case monitoringDisabled
    case monitoringPaused(reason: String)
    case monitoringResumed

    // MARK: - Text Detection Events
    case textFieldDetected(application: String)
    case textFieldLost
    case selectedTextDetected(application: String, length: Int)

    // MARK: - Suggestion Events
    case suggestionCategorySelected(category: String)
    case suggestionTypeSelected(type: String, category: String)
    case suggestionProcessingStarted(type: String)
    case suggestionProcessingCompleted(type: String, duration: TimeInterval)
    case suggestionProcessingFailed(type: String, error: String)
    case suggestionAccepted(type: String)
    case suggestionRejected(type: String)

    // MARK: - Text Injection Events
    case textInjectionStarted(application: String)
    case textInjectionSucceeded(application: String, method: String)
    case textInjectionFailed(application: String, error: String)

    // MARK: - UI Events
    case mainWindowOpened
    case mainWindowClosed
    case overlayDisplayed
    case overlayHidden
    case actionMenuOpened
    case actionMenuClosed
    case aboutWindowOpened
    case settingsOpened
    case statusBarMenuOpened

    // MARK: - Subscription Events
    case subscriptionViewed
    case subscriptionPurchaseStarted(plan: String)
    case subscriptionPurchaseCompleted(plan: String)
    case subscriptionPurchaseFailed(plan: String, error: String)
    case subscriptionCancelled

    // MARK: - Team Events
    case teamSwitched(teamId: String)
    case teamCreated
    case teamJoined(teamId: String)

    // MARK: - Error Events
    case errorOccurred(domain: String, code: String, message: String)
    case crashDetected(reason: String)

    // MARK: - Performance Events
    case performanceMetric(name: String, value: Double, unit: String)

    // MARK: - Custom Event
    case custom(name: String, parameters: [String: String])
}

// MARK: - Event Properties

extension AnalyticsEvent {
    /// The event name for analytics tracking
    var name: String {
        switch self {
        case .appLaunched: return "app_launched"
        case .appTerminated: return "app_terminated"
        case .appBecameActive: return "app_became_active"
        case .appResignedActive: return "app_resigned_active"

        case .loginStarted: return "login_started"
        case .loginSucceeded: return "login_succeeded"
        case .loginFailed: return "login_failed"
        case .logoutStarted: return "logout_started"
        case .logoutCompleted: return "logout_completed"
        case .tokenRefreshed: return "token_refreshed"
        case .tokenRefreshFailed: return "token_refresh_failed"

        case .accessibilityPermissionRequested: return "accessibility_permission_requested"
        case .accessibilityPermissionGranted: return "accessibility_permission_granted"
        case .accessibilityPermissionDenied: return "accessibility_permission_denied"
        case .monitoringEnabled: return "monitoring_enabled"
        case .monitoringDisabled: return "monitoring_disabled"
        case .monitoringPaused: return "monitoring_paused"
        case .monitoringResumed: return "monitoring_resumed"

        case .textFieldDetected: return "text_field_detected"
        case .textFieldLost: return "text_field_lost"
        case .selectedTextDetected: return "selected_text_detected"

        case .suggestionCategorySelected: return "suggestion_category_selected"
        case .suggestionTypeSelected: return "suggestion_type_selected"
        case .suggestionProcessingStarted: return "suggestion_processing_started"
        case .suggestionProcessingCompleted: return "suggestion_processing_completed"
        case .suggestionProcessingFailed: return "suggestion_processing_failed"
        case .suggestionAccepted: return "suggestion_accepted"
        case .suggestionRejected: return "suggestion_rejected"

        case .textInjectionStarted: return "text_injection_started"
        case .textInjectionSucceeded: return "text_injection_succeeded"
        case .textInjectionFailed: return "text_injection_failed"

        case .mainWindowOpened: return "main_window_opened"
        case .mainWindowClosed: return "main_window_closed"
        case .overlayDisplayed: return "overlay_displayed"
        case .overlayHidden: return "overlay_hidden"
        case .actionMenuOpened: return "action_menu_opened"
        case .actionMenuClosed: return "action_menu_closed"
        case .aboutWindowOpened: return "about_window_opened"
        case .settingsOpened: return "settings_opened"
        case .statusBarMenuOpened: return "status_bar_menu_opened"

        case .subscriptionViewed: return "subscription_viewed"
        case .subscriptionPurchaseStarted: return "subscription_purchase_started"
        case .subscriptionPurchaseCompleted: return "subscription_purchase_completed"
        case .subscriptionPurchaseFailed: return "subscription_purchase_failed"
        case .subscriptionCancelled: return "subscription_cancelled"

        case .teamSwitched: return "team_switched"
        case .teamCreated: return "team_created"
        case .teamJoined: return "team_joined"

        case .errorOccurred: return "error_occurred"
        case .crashDetected: return "crash_detected"

        case .performanceMetric: return "performance_metric"

        case .custom(let name, _): return name
        }
    }

    /// The event category for grouping
    var category: String {
        switch self {
        case .appLaunched, .appTerminated, .appBecameActive, .appResignedActive:
            return "app_lifecycle"
        case .loginStarted, .loginSucceeded, .loginFailed, .logoutStarted, .logoutCompleted,
             .tokenRefreshed, .tokenRefreshFailed:
            return "authentication"
        case .accessibilityPermissionRequested, .accessibilityPermissionGranted,
             .accessibilityPermissionDenied, .monitoringEnabled, .monitoringDisabled,
             .monitoringPaused, .monitoringResumed:
            return "accessibility"
        case .textFieldDetected, .textFieldLost, .selectedTextDetected:
            return "text_detection"
        case .suggestionCategorySelected, .suggestionTypeSelected, .suggestionProcessingStarted,
             .suggestionProcessingCompleted, .suggestionProcessingFailed,
             .suggestionAccepted, .suggestionRejected:
            return "suggestions"
        case .textInjectionStarted, .textInjectionSucceeded, .textInjectionFailed:
            return "text_injection"
        case .mainWindowOpened, .mainWindowClosed, .overlayDisplayed, .overlayHidden,
             .actionMenuOpened, .actionMenuClosed, .aboutWindowOpened, .settingsOpened,
             .statusBarMenuOpened:
            return "ui_interaction"
        case .subscriptionViewed, .subscriptionPurchaseStarted, .subscriptionPurchaseCompleted,
             .subscriptionPurchaseFailed, .subscriptionCancelled:
            return "subscription"
        case .teamSwitched, .teamCreated, .teamJoined:
            return "team"
        case .errorOccurred, .crashDetected:
            return "errors"
        case .performanceMetric:
            return "performance"
        case .custom:
            return "custom"
        }
    }

    /// Event parameters as dictionary
    var parameters: [String: Any] {
        var params: [String: Any] = [
            "event_category": category,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        switch self {
        case .loginSucceeded(let provider):
            params["provider"] = provider
        case .loginFailed(let error):
            params["error"] = error
        case .tokenRefreshFailed(let error):
            params["error"] = error

        case .monitoringPaused(let reason):
            params["reason"] = reason

        case .textFieldDetected(let application):
            params["application"] = application
        case .selectedTextDetected(let application, let length):
            params["application"] = application
            params["text_length"] = length

        case .suggestionCategorySelected(let category):
            params["category"] = category
        case .suggestionTypeSelected(let type, let category):
            params["suggestion_type"] = type
            params["category"] = category
        case .suggestionProcessingStarted(let type):
            params["suggestion_type"] = type
        case .suggestionProcessingCompleted(let type, let duration):
            params["suggestion_type"] = type
            params["duration_seconds"] = duration
        case .suggestionProcessingFailed(let type, let error):
            params["suggestion_type"] = type
            params["error"] = error
        case .suggestionAccepted(let type):
            params["suggestion_type"] = type
        case .suggestionRejected(let type):
            params["suggestion_type"] = type

        case .textInjectionStarted(let application):
            params["application"] = application
        case .textInjectionSucceeded(let application, let method):
            params["application"] = application
            params["injection_method"] = method
        case .textInjectionFailed(let application, let error):
            params["application"] = application
            params["error"] = error

        case .subscriptionPurchaseStarted(let plan):
            params["plan"] = plan
        case .subscriptionPurchaseCompleted(let plan):
            params["plan"] = plan
        case .subscriptionPurchaseFailed(let plan, let error):
            params["plan"] = plan
            params["error"] = error

        case .teamSwitched(let teamId):
            params["team_id"] = teamId
        case .teamJoined(let teamId):
            params["team_id"] = teamId

        case .errorOccurred(let domain, let code, let message):
            params["error_domain"] = domain
            params["error_code"] = code
            params["error_message"] = message
        case .crashDetected(let reason):
            params["crash_reason"] = reason

        case .performanceMetric(let name, let value, let unit):
            params["metric_name"] = name
            params["metric_value"] = value
            params["metric_unit"] = unit

        case .custom(_, let customParams):
            for (key, value) in customParams {
                params[key] = value
            }

        default:
            break
        }

        return params
    }
}

// MARK: - User Properties

/// User properties that can be set for analytics
struct AnalyticsUserProperties: Sendable {
    let userId: String?
    let email: String?
    let subscriptionTier: String?
    let teamId: String?
    let appVersion: String
    let osVersion: String
    let deviceModel: String

    init(
        userId: String? = nil,
        email: String? = nil,
        subscriptionTier: String? = nil,
        teamId: String? = nil
    ) {
        self.userId = userId
        self.email = email
        self.subscriptionTier = subscriptionTier
        self.teamId = teamId
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        self.deviceModel = "Mac"
    }

    var asDictionary: [String: String] {
        var dict: [String: String] = [
            "app_version": appVersion,
            "os_version": osVersion,
            "device_model": deviceModel
        ]

        if let userId = userId { dict["user_id"] = userId }
        if let email = email { dict["email_domain"] = email.components(separatedBy: "@").last ?? "unknown" }
        if let subscriptionTier = subscriptionTier { dict["subscription_tier"] = subscriptionTier }
        if let teamId = teamId { dict["team_id"] = teamId }

        return dict
    }
}

