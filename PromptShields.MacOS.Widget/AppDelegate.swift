import AppKit
import RevenueCat
import os
import SwiftUI

/// Application delegate responsible for handling application lifecycle events
/// Manages third-party service configurations and app initialization
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties
    
    /// Logger for application delegate events
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppDelegate.self)
    )
    
    /// Status bar item for the system menu
    private var statusBarItem: NSStatusItem?
    
    // MARK: - NSApplicationDelegate Methods
    
    /// Called when the application has finished launching
    /// Configures third-party services and performs initial setup
    /// - Parameter notification: Notification containing launch information
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureRevenueCat()
        setupStatusBarMenu()
        
        // Prevent the app from terminating when all windows are closed
        NSApp.setActivationPolicy(.accessory)
        
        logger.info("Application finished launching successfully")
    }
    
    /// Called when the last window is closed
    /// Prevents the app from terminating when windows are closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Switch back to accessory mode when all windows are closed
        NSApp.setActivationPolicy(.accessory)
        return false
    }
    
    /// Called when the application is about to hide
    /// Switches back to accessory mode
    func applicationWillHide(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func setupStatusBarMenu() {
        // Create status bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set the status bar icon (using the app's logo)
        if let button = statusBarItem?.button {
            button.image = NSImage(named: "logo_status_bar")
            button.imagePosition = .imageLeft
            button.toolTip = "PromptShields"
            logger.info("Status bar item created successfully")
        } else {
            logger.error("Failed to create status bar button")
        }
        
        // Create the menu
        let menu = NSMenu()
        
        // Add "Show PromptShields" menu item
        let openMainWindowItem = NSMenuItem(
            title: "Show PromptShields",
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        openMainWindowItem.target = self
        menu.addItem(openMainWindowItem)
        
        // Add separator
        menu.addItem(NSMenuItem.separator())
        
        // Add "About" menu item
        let aboutItem = NSMenuItem(
            title: "About PromptShields",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        // Add separator
        menu.addItem(NSMenuItem.separator())
        
        // Add "Quit" menu item
        let quitItem = NSMenuItem(
            title: "Quit PromptShields",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        // Set the menu to the status bar item
        statusBarItem?.menu = menu
    }
    
    @MainActor
    @objc private func openMainWindow() {
        logger.info("Opening main window...")
        
        // Temporarily change activation policy to show windows
        NSApp.setActivationPolicy(.regular)
        
        // Find and show the main window
        if let mainWindow = NSApp.windows.first(where: { 
            $0.identifier?.rawValue == MainApp.mainWindow 
        }) {
            logger.info("Found main window, showing it...")
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            logger.info("Main window not found, will retry...")
            // If main window doesn't exist, try to create it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                if let mainWindow = NSApp.windows.first(where: {
                    $0.identifier?.rawValue == MainApp.mainWindow 
                }) {
                    self?.logger.info("Found main window on retry, showing it...")
                    if mainWindow.isMiniaturized {
                        mainWindow.deminiaturize(nil)
                    }
                    mainWindow.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    self?.logger.error("Main window still not found after retry")
                }
            }
        }
    }
    
    /// Shows the about dialog
    @MainActor
    @objc private func showAbout() {
        // Temporarily change activation policy to show windows
        NSApp.setActivationPolicy(.regular)
        
        let aboutWindow = AboutWindow()
        aboutWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Configures RevenueCat for in-app purchase management
    /// This method sets up the RevenueCat SDK with the appropriate API key
    private func configureRevenueCat() {
        Purchases.configure(withAPIKey: revenueCatAPIKey)
        logger.info("RevenueCat configured successfully")
    }
}
