import AppKit
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
        logger.info("Application did finish launching - starting setup...")

        // Clean up any hanging windows first
        cleanupHangingWindows()

        // Test just the activation policy change first
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.logger.info("Setting activation policy to accessory...")
//            NSApp.setActivationPolicy(.accessory)
        }

        logger.info("Application finished launching successfully")
        setupStatusBarMenu()
    }

    /// Called when the last window is closed
    /// Prevents the app from terminating when windows are closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Switch back to accessory mode when all windows are closed
//        NSApp.setActivationPolicy(.accessory)
        return false
    }

    /// Called when the application is about to hide
    /// Switches back to accessory mode
    func applicationWillHide(_ notification: Notification) {
//        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Private Methods

    @MainActor
    private func setupStatusBarMenu() {
        logger.info("Starting status bar menu setup...")

        // Create status bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusBarItem = statusBarItem else {
            logger.error("Failed to create status bar item")
            return
        }

        // Set the status bar icon (using the app's logo)
        if let button = statusBarItem.button {
            // Use a simple text fallback first to avoid image loading issues
            button.title = "PS"
            button.toolTip = "PromptShields"

            // Try to load the image after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let image = NSImage(named: "logo_status_bar") {
                    button.image = image
                    button.title = ""
                    button.imagePosition = .imageLeft
                    self.logger.info("Status bar item created successfully with image")
                } else {
                    self.logger.error("Failed to load status bar image, keeping text fallback")
                }
            }
        } else {
            logger.error("Failed to create status bar button")
            return
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
        statusBarItem.menu = menu

        logger.info("Status bar menu setup completed successfully")
    }

    @MainActor
    @objc private func openMainWindow() {
        logger.info("Opening main window...")

        // Clean up any hanging windows first
        cleanupHangingWindows(windowIdentifiers: [MainApp.mainWindow])

        // Temporarily change activation policy to show windows
        NSApp.setActivationPolicy(.regular)

        // Find and show the main window
        if let mainWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix(MainApp.mainWindow) ?? false
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
                    $0.identifier?.rawValue.hasPrefix(MainApp.mainWindow) ?? false
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

    @MainActor
    private func cleanupHangingWindows(windowIdentifiers: [String] = [MainApp.mainWindow, MainApp.overlayRender, MainApp.actionRender]) {
        logger.info("Cleaning up hanging windows...")
        let existingWindows = NSApp.windows

        for window in existingWindows {
            if let identifier = window.identifier?.rawValue,
               windowIdentifiers.contains(identifier) {
                logger.info("Closing hanging window with identifier: \(identifier)")
                window.close()
            }
        }

        logger.info("Window cleanup completed")
    }
}

// MARK: - NSWindowDelegate
extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                _ = self.windowShouldClose(sender)
            }
            return false
        }

        if sender.identifier?.rawValue.hasPrefix(MainApp.mainWindow) ?? false {
            logger.info("Main window close requested, minimizing instead...")
            // Minimize the window instead of closing it
            sender.miniaturize(nil)
            // Switch back to accessory mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                NSApp.setActivationPolicy(.accessory)
            }
            return false
        }
        return true
    }
}
