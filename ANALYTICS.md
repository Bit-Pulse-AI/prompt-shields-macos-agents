# PromptShields Analytics Documentation

This document describes the analytics telemetry system implemented in the PromptShields macOS Widget application.

## Overview

The analytics system is built with a pluggable architecture that follows SOLID principles:

- **Single Responsibility**: Each tracker handles only its own implementation
- **Open/Closed**: Easy to add new trackers without modifying existing code
- **Interface Segregation**: Clean protocol for all trackers
- **Dependency Inversion**: Code depends on abstractions (protocol), not concrete implementations

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AnalyticsManager                         │
│                    (Orchestrator)                           │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐                │
│  │ GoogleAnalytics  │  │ ConsoleTracker   │  ... (more)    │
│  │    Tracker       │  │   (Debug)        │                │
│  └──────────────────┘  └──────────────────┘                │
├─────────────────────────────────────────────────────────────┤
│                  AnalyticsTracker Protocol                  │
└─────────────────────────────────────────────────────────────┘
```

## Configuration

### Google Analytics Setup

1. Create a GA4 property in Google Analytics
2. Get your Measurement ID (format: `G-XXXXXXXXXX`)
3. Create a Measurement Protocol API secret
4. Configure in `Const.swift` or environment variables:

```swift
// Option 1: Environment variables (recommended for security)
GA_MEASUREMENT_ID=G-XXXXXXXXXX
GA_API_SECRET=your_api_secret

// Option 2: In Const.swift
enum Const {
    enum Analytics {
        static let googleMeasurementId = "G-XXXXXXXXXX"
        static let googleApiSecret = "your_api_secret"
    }
}
```

### Enabling/Disabling Analytics

```swift
// Programmatically
await AnalyticsManager.shared.setEnabled(false)

// User preference is persisted in UserDefaults
// Key: "analytics_enabled"
```

## Events Reference

### App Lifecycle Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `app_launched` | app_lifecycle | App started | - |
| `app_terminated` | app_lifecycle | App is terminating | - |
| `app_became_active` | app_lifecycle | App came to foreground | - |
| `app_resigned_active` | app_lifecycle | App went to background | - |

**Tracked in**: `AppDelegate.swift`

### Authentication Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `login_started` | authentication | User initiated login | - |
| `login_succeeded` | authentication | Login completed successfully | `provider` |
| `login_failed` | authentication | Login failed | `error` |
| `logout_started` | authentication | User initiated logout | - |
| `logout_completed` | authentication | Logout completed | - |
| `token_refreshed` | authentication | Auth token refreshed | - |
| `token_refresh_failed` | authentication | Token refresh failed | `error` |

**Tracked in**: `AuthManager.swift` (pending integration)

### Accessibility Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `accessibility_permission_requested` | accessibility | Permission dialog shown | - |
| `accessibility_permission_granted` | accessibility | User granted permission | - |
| `accessibility_permission_denied` | accessibility | User denied/timeout | - |
| `monitoring_enabled` | accessibility | Monitoring started | - |
| `monitoring_disabled` | accessibility | Monitoring stopped | - |
| `monitoring_paused` | accessibility | Monitoring paused | `reason` |
| `monitoring_resumed` | accessibility | Monitoring resumed | - |

**Tracked in**: `AccessibilityManager.swift`

### Text Detection Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `text_field_detected` | text_detection | Text field found | `application` |
| `text_field_lost` | text_detection | Text field lost focus | - |
| `selected_text_detected` | text_detection | User selected text | `application`, `text_length` |

**Tracked in**: `AccessibilityManager.swift`

### Suggestion Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `suggestion_category_selected` | suggestions | User selected category | `category` |
| `suggestion_type_selected` | suggestions | User selected suggestion type | `type`, `category` |
| `suggestion_processing_started` | suggestions | LLM processing began | `type` |
| `suggestion_processing_completed` | suggestions | LLM processing finished | `type`, `duration_seconds` |
| `suggestion_processing_failed` | suggestions | LLM processing failed | `type`, `error` |
| `suggestion_accepted` | suggestions | User accepted suggestion | `type` |
| `suggestion_rejected` | suggestions | User rejected suggestion | `type` |

**Tracked in**: `ActionView.swift`

### Text Injection Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `text_injection_started` | text_injection | Injection attempt began | `application` |
| `text_injection_succeeded` | text_injection | Text successfully injected | `application`, `injection_method` |
| `text_injection_failed` | text_injection | Injection failed | `application`, `error` |

**Tracked in**: `ActionView.swift`, `TextInjectionService.swift`

### UI Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `main_window_opened` | ui_interaction | Main window shown | - |
| `main_window_closed` | ui_interaction | Main window hidden | - |
| `overlay_displayed` | ui_interaction | Overlay appeared | - |
| `overlay_hidden` | ui_interaction | Overlay hidden | - |
| `action_menu_opened` | ui_interaction | Action menu opened | - |
| `action_menu_closed` | ui_interaction | Action menu closed | - |
| `about_window_opened` | ui_interaction | About dialog shown | - |
| `settings_opened` | ui_interaction | Settings viewed | - |
| `status_bar_menu_opened` | ui_interaction | Status bar menu clicked | - |

**Tracked in**: `AppDelegate.swift`, `ActionView.swift`

### Subscription Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `subscription_viewed` | subscription | Pricing page viewed | - |
| `subscription_purchase_started` | subscription | Purchase flow started | `plan` |
| `subscription_purchase_completed` | subscription | Purchase successful | `plan` |
| `subscription_purchase_failed` | subscription | Purchase failed | `plan`, `error` |
| `subscription_cancelled` | subscription | Subscription cancelled | - |

**Tracked in**: `SubscriptionView.swift` (pending integration)

### Team Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `team_switched` | team | User switched teams | `team_id` |
| `team_created` | team | New team created | - |
| `team_joined` | team | User joined team | `team_id` |

**Tracked in**: `TeamView.swift` (pending integration)

### Error Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `error_occurred` | errors | Application error | `error_domain`, `error_code`, `error_message` |
| `crash_detected` | errors | Crash detected | `crash_reason` |

**Tracked in**: Throughout application

### Performance Events

| Event Name | Category | Description | Parameters |
|------------|----------|-------------|------------|
| `performance_metric` | performance | Performance measurement | `metric_name`, `metric_value`, `metric_unit` |

**Tracked in**: Via `AnalyticsManager.measureAsync()`

## User Properties

The following user properties are tracked:

| Property | Description |
|----------|-------------|
| `user_id` | Unique user identifier (if logged in) |
| `email_domain` | Domain part of user email |
| `subscription_tier` | Current subscription level |
| `team_id` | Active team identifier |
| `app_version` | Application version |
| `os_version` | macOS version |
| `device_model` | Always "Mac" |

## Usage Examples

### Track a simple event

```swift
// Fire-and-forget (recommended for UI events)
Analytics.trackAsync(.mainWindowOpened)

// Awaitable version
await Analytics.track(.loginSucceeded(provider: "auth0"))
```

### Track with custom parameters

```swift
Analytics.trackAsync(.custom(
    name: "feature_used",
    parameters: ["feature": "dark_mode", "enabled": "true"]
))
```

### Track an error

```swift
await AnalyticsManager.shared.trackError(error, domain: "network")
```

### Measure performance

```swift
let result = await AnalyticsManager.shared.measureAsync(name: "api_call") {
    try await apiClient.fetchData()
}
```

### Set user properties

```swift
await AnalyticsManager.shared.updateUserProperties(
    userId: "user123",
    email: "user@example.com",
    subscriptionTier: "premium",
    teamId: "team456"
)
```

## Adding a New Tracker

1. Create a new class conforming to `AnalyticsTracker`:

```swift
actor MyCustomTracker: AnalyticsTracker {
    nonisolated let identifier = "my_custom_tracker"
    nonisolated var isEnabled: Bool { true }
    
    func initialize() async { /* Setup */ }
    func track(_ event: AnalyticsEvent) async { /* Send event */ }
    func setUserProperties(_ properties: AnalyticsUserProperties) async { /* Set props */ }
    func reset() async { /* Clear state */ }
    func flush() async { /* Send pending */ }
    func setEnabled(_ enabled: Bool) async { /* Toggle */ }
}
```

2. Register in `AnalyticsManager`:

```swift
await AnalyticsManager.shared.addTracker(MyCustomTracker())
```

3. Remove when no longer needed:

```swift
await AnalyticsManager.shared.removeTracker(identifier: "my_custom_tracker")
```

## Privacy Considerations

- Analytics can be disabled by users via settings
- Email addresses are anonymized (only domain tracked)
- No PII (Personally Identifiable Information) is collected
- Text content is never tracked, only metadata
- Client ID is randomly generated and stored locally

## Debug Mode

In DEBUG builds, a console tracker is automatically added that logs all events to the Xcode console with the 📊 prefix.

```
📊 [suggestions] suggestion_processing_completed - {type: grammar_check, duration_seconds: 1.234}
```

## Files

| File | Purpose |
|------|---------|
| `AnalyticsEvent.swift` | Event definitions and parameters |
| `AnalyticsTracker.swift` | Protocol and configuration |
| `AnalyticsManager.swift` | Central orchestrator |
| `GoogleAnalyticsTracker.swift` | GA4 implementation |
| `ConsoleAnalyticsTracker.swift` | Debug logging |
| `Const.swift` | Configuration constants |

## Version History

| Version | Changes |
|---------|---------|
| 1.0.0 | Initial analytics implementation |

