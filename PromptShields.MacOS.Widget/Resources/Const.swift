import Foundation

// MARK: - API Configuration

let baseURL = "https://apim-3n5enx234xc3g.azure-api.net/fjords/api/v1"
// let baseURL = "http://localhost:8000/api/v1"

let webBillingScheme = "promptshields"
let webBillingSuccessURL = "\(webBillingScheme)://success"
let webBillingCancelURL = "\(webBillingScheme)://cancel"
let googleMeasurementId = ""
let googleApiSecret = ""
let isEnabledByDefault = true
let debugModeEnabled = false
 
enum App {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "ai.promptshields.widget"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
}
