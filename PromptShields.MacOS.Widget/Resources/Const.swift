import Foundation

// MARK: - API Configuration

 let baseURL = "https://apim-3n5enx234xc3g.azure-api.net/fjords/api/v1"
// let baseURL = "http://localhost:8000/api/v1"

// MARK: - Web Billing Configuration

let webBillingScheme = "promptshields"
let webBillingSuccessURL = "\(webBillingScheme)://success"
let webBillingCancelURL = "\(webBillingScheme)://cancel"

// MARK: - Analytics Configuration

let googleMeasurementId = "G-MX58JJXZT6"
let googleApiSecret = "ukE_xXW-TyKrHO5nWl1SCA"
let postHogApiKey = "phc_W36fXFCOap60fyEAoj4RqTIBpwg1toe9O5XCJvxLIRn"
let postHogHost = "https://eu.i.posthog.com"
let firebaseApiKey = "AIzaSyCN72aGg--8La6Oq43slhg-A5DBWSFHTfA"
let firebaseProjectId = "promptshields---dev"
let firebaseAppId = "1:173256827283:web:c69c632f462435513b8866"

/// Whether analytics is enabled by default
let analyticsEnabledByDefault = true

// MARK: - App Configuration

let bundleIdentifier = Bundle.main.bundleIdentifier ?? "ai.promptshields.widget"
let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
