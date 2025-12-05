import Foundation

// MARK: - API Configuration

let baseURL = "https://apim-3n5enx234xc3g.azure-api.net/fjords/api/v1"
// let baseURL = "http://localhost:8000/api/v1"

// MARK: - Web Billing Configuration

let webBillingScheme = "promptshields"
let webBillingSuccessURL = "\(webBillingScheme)://success"
let webBillingCancelURL = "\(webBillingScheme)://cancel"

// MARK: - Analytics Configuration

/// Google Analytics 4 Measurement ID (format: G-XXXXXXXXXX)
let googleMeasurementId = ""
/// Google Analytics 4 API Secret
let googleApiSecret = ""

/// PostHog API Key (from PostHog Project Settings)
let postHogApiKey = ""
/// PostHog Host URL (default: https://app.posthog.com or your self-hosted instance)
let postHogHost = "https://app.posthog.com"

/// Firebase Web API Key (for REST API access)
let firebaseApiKey = ""
/// Firebase Project ID
let firebaseProjectId = ""
/// Firebase App ID
let firebaseAppId = ""

/// Whether analytics is enabled by default
let analyticsEnabledByDefault = true

// MARK: - App Configuration

let bundleIdentifier = Bundle.main.bundleIdentifier ?? "ai.promptshields.widget"
let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
