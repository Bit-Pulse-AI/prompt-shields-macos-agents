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
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AnalyticsManager                                  │
│                           (Orchestrator)                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │ GoogleAnalytics  │  │   PostHog        │  │    Firebase      │          │
│  │    Tracker       │  │   Tracker        │  │    Tracker       │          │
│  │  (GA4 Events)    │  │  (Product)       │  │  (Perf/Crashes)  │          │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘          │
│                                                                             │
│  ┌──────────────────┐                                                       │
│  │ ConsoleTracker   │  ... (extensible)                                     │
│  │   (Debug)        │                                                       │
│  └──────────────────┘                                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                       AnalyticsTracker Protocol                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Trackers Overview

| Tracker | Purpose | API Used |
|---------|---------|----------|
| **Google Analytics** | General event tracking, user behavior | GA4 Measurement Protocol |
| **PostHog** | Product analytics, feature usage, user journeys | PostHog Capture API |
| **Firebase** | Performance monitoring, crash reporting | Firebase REST APIs |
| **Console** | Debug logging (DEBUG builds only) | os.Logger |

## Configuration

### Google Analytics Setup

1. Create a GA4 property in [Google Analytics](https://analytics.google.com)
2. Get your Measurement ID (format: `G-XXXXXXXXXX`) from Admin > Data Streams
3. Create a Measurement Protocol API secret from the same location
4. Configure in `Const.swift`:

```swift
let googleMeasurementId = "G-XXXXXXXXXX"
let googleApiSecret = "your_api_secret"
```

### PostHog Setup

1. Create a project at [PostHog](https://posthog.com) or your self-hosted instance
2. Get your API key from Project Settings
3. Configure in `Const.swift`:

```swift
let postHogApiKey = "phc_your_api_key"
let postHogHost = "https://app.posthog.com"  // or your self-hosted URL
```

### Firebase Setup

1. Create a project in [Firebase Console](https://console.firebase.google.com)
2. Add a macOS app to your project
3. Get your configuration from Project Settings > General
4. Configure in `Const.swift`:

```swift
let firebaseApiKey = "your_web_api_key"
let firebaseProjectId = "your-project-id"
let firebaseAppId = "1:123456789:macos:abcdef"
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

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `app_launched` | app_lifecycle | App started | - | All |
| `app_terminated` | app_lifecycle | App is terminating | - | All |
| `app_became_active` | app_lifecycle | App came to foreground | - | All |
| `app_resigned_active` | app_lifecycle | App went to background | - | All |

**Tracked in**: `AppDelegate.swift`

### Authentication Events

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `login_started` | authentication | User initiated login | - | All |
| `login_succeeded` | authentication | Login completed successfully | `provider` | All |
| `login_failed` | authentication | Login failed | `error` | All + Firebase (error) |
| `logout_started` | authentication | User initiated logout | - | All |
| `logout_completed` | authentication | Logout completed | - | All |
| `token_refreshed` | authentication | Auth token refreshed | - | All |
| `token_refresh_failed` | authentication | Token refresh failed | `error` | All + Firebase (error) |

**Tracked in**: `AuthManager.swift`

### Accessibility Events

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `accessibility_permission_requested` | accessibility | Permission dialog shown | - | All |
| `accessibility_permission_granted` | accessibility | User granted permission | - | All |
| `accessibility_permission_denied` | accessibility | User denied/timeout | - | All |
| `monitoring_enabled` | accessibility | Monitoring started | - | All |
| `monitoring_disabled` | accessibility | Monitoring stopped | - | All |
| `monitoring_paused` | accessibility | Monitoring paused | `reason` | All |
| `monitoring_resumed` | accessibility | Monitoring resumed | - | All |

**Tracked in**: `AccessibilityManager.swift`

### Text Detection Events

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `text_field_detected` | text_detection | Text field found | `application` | All |
| `text_field_lost` | text_detection | Text field lost focus | - | All |
| `selected_text_detected` | text_detection | User selected text | `application`, `text_length` | All |

**Tracked in**: `AccessibilityManager.swift`

### Suggestion Events

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `suggestion_category_selected` | suggestions | User selected category | `category` | GA, PostHog |
| `suggestion_type_selected` | suggestions | User selected suggestion type | `type`, `category` | GA, PostHog |
| `suggestion_processing_started` | suggestions | LLM processing began | `type` | All + Firebase (trace) |
| `suggestion_processing_completed` | suggestions | LLM processing finished | `type`, `duration_seconds` | All + Firebase (trace) |
| `suggestion_processing_failed` | suggestions | LLM processing failed | `type`, `error` | All + Firebase (error) |
| `suggestion_accepted` | suggestions | User accepted suggestion | `type` | All |
| `suggestion_rejected` | suggestions | User rejected suggestion | `type` | All |

**Tracked in**: `ActionView.swift`

**Firebase Performance**: Automatically creates traces for `suggestion_[type]` operations.

### Text Injection Events

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `text_injection_started` | text_injection | Injection attempt began | `application` | All + Firebase (trace) |
| `text_injection_succeeded` | text_injection | Text successfully injected | `application`, `injection_method` | All + Firebase (trace) |
| `text_injection_failed` | text_injection | Injection failed | `application`, `error` | All + Firebase (error) |

**Tracked in**: `ActionView.swift`, `TextInjectionService.swift`

**Firebase Performance**: Automatically creates traces for `text_injection_[app]` operations.

### UI Events

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `main_window_opened` | ui_interaction | Main window shown | - | GA, PostHog |
| `main_window_closed` | ui_interaction | Main window hidden | - | GA, PostHog |
| `overlay_displayed` | ui_interaction | Overlay appeared | - | GA, PostHog |
| `overlay_hidden` | ui_interaction | Overlay hidden | - | GA, PostHog |
| `action_menu_opened` | ui_interaction | Action menu opened | - | GA, PostHog |
| `action_menu_closed` | ui_interaction | Action menu closed | - | GA, PostHog |
| `about_window_opened` | ui_interaction | About dialog shown | - | GA, PostHog |
| `settings_opened` | ui_interaction | Settings viewed | - | GA, PostHog |
| `status_bar_menu_opened` | ui_interaction | Status bar menu clicked | - | GA, PostHog |

**Tracked in**: `AppDelegate.swift`, `ActionView.swift`

### Subscription Events

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `subscription_viewed` | subscription | Pricing page viewed | - | All |
| `subscription_purchase_started` | subscription | Purchase flow started | `plan` | All |
| `subscription_purchase_completed` | subscription | Purchase successful | `plan` | All |
| `subscription_purchase_failed` | subscription | Purchase failed | `plan`, `error` | All + Firebase (error) |
| `subscription_cancelled` | subscription | Subscription cancelled | - | All |

**Tracked in**: `SubscriptionView.swift`

### Team Events

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `team_switched` | team | User switched teams | `team_id` | All |
| `team_created` | team | New team created | - | All |
| `team_joined` | team | User joined team | `team_id` | All |

**Tracked in**: `TeamView.swift`

### Error Events

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `error_occurred` | errors | Application error | `error_domain`, `error_code`, `error_message` | All + Firebase (non-fatal) |
| `crash_detected` | errors | Crash detected | `crash_reason` | Firebase (fatal) |

**Tracked in**: Throughout application

### Performance Events

| Event Name | Category | Description | Parameters | Trackers |
|------------|----------|-------------|------------|----------|
| `performance_metric` | performance | Performance measurement | `metric_name`, `metric_value`, `metric_unit` | Firebase |

**Tracked in**: Via `AnalyticsManager.measureAsync()`

## Firebase-Specific Features

### Performance Traces

Firebase automatically tracks these operations as performance traces:

| Trace Name | Triggered By | Measures |
|------------|--------------|----------|
| `app_startup` | `app_launched` | App launch time |
| `suggestion_[type]` | Suggestion processing | LLM response time |
| `text_injection_[app]` | Text injection | Injection duration |

### Crash Reporting

Firebase captures:
- Fatal crashes with stack traces
- Non-fatal errors (from `error_occurred` events)
- App state at time of crash (memory, disk usage)
- User context (user ID, subscription tier)

Crashes are:
1. Persisted locally if they can't be sent immediately
2. Sent on next app launch

### Custom Traces

```swift
// Start a trace
await firebaseTracker.startTrace(name: "my_operation")

// Add attributes during operation
await firebaseTracker.addAttribute(traceName: "my_operation", key: "step", value: "processing")

// Increment counters
await firebaseTracker.incrementCounter(traceName: "my_operation", counterName: "items_processed")

// End trace
await firebaseTracker.endTrace(name: "my_operation")
```

## PostHog-Specific Features

### User Identification

PostHog automatically tracks:
- Distinct ID (persistent across sessions)
- User properties ($set and $set_once)
- Device and OS information

### Session Tracking

PostHog groups events by session automatically based on:
- Distinct ID
- Timestamps
- Session timeout (30 minutes of inactivity)

## User Properties

The following user properties are tracked across all trackers:

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

2. Add to `TrackerType` enum in `AnalyticsTracker.swift`:

```swift
enum TrackerType: String, CaseIterable, Sendable {
    case myCustom = "my_custom"
    // ...
}
```

3. Register in `AnalyticsManager.initialize()`:

```swift
await addTracker(MyCustomTracker())
```

4. Remove when no longer needed:

```swift
await AnalyticsManager.shared.removeTracker(identifier: "my_custom_tracker")
```

## Privacy Considerations

- Analytics can be disabled by users via settings
- Email addresses are anonymized (only domain tracked)
- No PII (Personally Identifiable Information) is collected
- Text content is never tracked, only metadata
- Client/distinct IDs are randomly generated and stored locally
- Crash reports include stack traces but no user data

## Debug Mode

In DEBUG builds:
1. Console tracker logs all events with 📊 prefix
2. All trackers use shorter flush intervals (5s vs 30s)
3. Smaller batch sizes for immediate feedback
4. Verbose logging enabled

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
| `PostHogTracker.swift` | PostHog implementation |
| `FirebaseTracker.swift` | Firebase Performance & Crashlytics |
| `ConsoleAnalyticsTracker.swift` | Debug logging |
| `Const.swift` | Configuration constants |

## Tracker Comparison

| Feature | Google Analytics | PostHog | Firebase |
|---------|-----------------|---------|----------|
| Event Tracking | ✅ | ✅ | Performance events only |
| User Properties | ✅ | ✅ | Custom keys |
| Session Tracking | ✅ | ✅ | - |
| Funnels | ✅ | ✅ | - |
| Performance Traces | - | - | ✅ |
| Crash Reporting | - | - | ✅ |
| Feature Flags | - | ✅ | - |
| Self-Hosted | - | ✅ | - |

## Version History

| Version | Changes |
|---------|---------|
| 1.0.0 | Initial analytics implementation with Google Analytics |
| 1.1.0 | Added PostHog tracker for product analytics |
| 1.2.0 | Added Firebase tracker for performance and crash reporting |
