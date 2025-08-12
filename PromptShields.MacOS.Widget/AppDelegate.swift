import AppKit
import RevenueCat
import os

/// Application delegate responsible for handling application lifecycle events
/// Manages third-party service configurations and app initialization
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    /// Logger for application delegate events
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppDelegate.self)
    )
    
    // MARK: - NSApplicationDelegate Methods
    
    /// Called when the application has finished launching
    /// Configures third-party services and performs initial setup
    /// - Parameter notification: Notification containing launch information
    func applicationDidFinishLaunching(_ notification: Notification) {
//        configureRevenueCat()
        logger.info("Application finished launching successfully")
    }
    
    // MARK: - Private Methods
    
    /// Configures RevenueCat for in-app purchase management
    /// This method sets up the RevenueCat SDK with the appropriate API key
    private func configureRevenueCat() {
        Purchases.configure(withAPIKey: revenueCatAPIKey)
        logger.info("RevenueCat configured successfully")
    }
}
