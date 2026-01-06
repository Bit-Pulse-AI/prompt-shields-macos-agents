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
        logger.debug("Application did finish launching - starting setup...")

        // Initialize analytics
        Task { @MainActor in
            await AnalyticsManager.shared.initialize()
        }

        // Setup status bar menu immediately
        setupStatusBarMenu()

        // Configure windows after a short delay to ensure SwiftUI has created them
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.configureAllWindows()
        }

        logger.debug("Application finished launching successfully")
    }

    /// Called when the last window is closed
    /// Prevents the app from terminating when windows are closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Called when the application is about to terminate
    func applicationWillTerminate(_ notification: Notification) {
        Analytics.trackAsync(.appTerminated)

        // Flush analytics before termination
        Task { @MainActor in
            await AnalyticsManager.shared.flush()
        }
    }

    /// Called when the application becomes active
    func applicationDidBecomeActive(_ notification: Notification) {
        Analytics.trackAsync(.appBecameActive)
    }

    /// Called when the application resigns active
    func applicationWillResignActive(_ notification: Notification) {
        Analytics.trackAsync(.appResignedActive)
    }

    /// Called when the application is about to hide
    func applicationWillHide(_ notification: Notification) {
        // No action needed
    }

    // MARK: - Window Configuration

    /// Configures all overlay and action windows to ensure they display properly
    @MainActor
    private func configureAllWindows() {
        logger.debug("Configuring all windows...")

        // Configure overlay window
        if let overlayWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix(MainApp.overlayRender) ?? false
        }) {
            configureFloatingWindow(overlayWindow, name: "overlay")
        } else {
            logger.debug("Overlay window not found")
        }

        // Configure action window
        if let actionWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix(MainApp.actionRender) ?? false
        }) {
            configureFloatingWindow(actionWindow, name: "action")
        } else {
            logger.debug("Action window not found")
        }

        logger.debug("Window configuration completed")
    }

    /// Configures a floating window with the correct properties
    @MainActor
    private func configureFloatingWindow(_ window: NSWindow, name: String) {
        // Essential: Don't let the system restore or auto-save window state
        window.isRestorable = false
        window.setFrameAutosaveName("")

        // Make window transparent
        window.isOpaque = false
        window.backgroundColor = .clear

        // Set window level to screenSaver (ensures visibility above other apps in release mode)
        window.level = .screenSaver

        // Remove shadow for cleaner appearance
        window.hasShadow = false

        // Remove title bar if present
        if window.styleMask.contains(.titled) {
            window.styleMask.remove(.titled)
    }

        // Allow window to appear on all spaces and in full screen
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Prevent window from being moved by dragging
        window.isMovableByWindowBackground = false

        // IMPORTANT: Keep window at minimal size initially, hidden off-screen
        // This prevents release mode from optimizing away "empty" windows
        if window.frame.width <= 0 || window.frame.height <= 0 {
            window.setFrame(CGRect(x: -10000, y: -10000, width: 1, height: 1), display: false)
            window.alphaValue = 0.0
        }

        logger.debug("Configured \(name) window successfully")
    }

    // MARK: - Status Bar Menu

    @MainActor
    private func setupStatusBarMenu() {
        logger.debug("Starting status bar menu setup...")

        // Create status bar item
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusBarItem = statusBarItem else {
            logger.debug("Failed to create status bar item")
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
                    self.logger.debug("Status bar item created successfully with image")
                } else {
                    self.logger.debug("Failed to load status bar image, keeping text fallback")
                }
            }
        } else {
            logger.debug("Failed to create status bar button")
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

        logger.debug("Status bar menu setup completed successfully")
    }

    @MainActor
    @objc private func openMainWindow() {
        logger.debug("Opening main window...")

        // Track event
        Analytics.trackAsync(.mainWindowOpened)

        // Temporarily change activation policy to show windows
        NSApp.setActivationPolicy(.regular)

        // Find and show the main window
        if let mainWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix(MainApp.mainWindow) ?? false
        }) {
            logger.debug("Found main window, showing it...")
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            logger.debug("Main window not found")
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
            logger.debug("Main window close requested, minimizing instead...")
            // Minimize the window instead of closing it
            sender.miniaturize(nil)
            return false
        }
        return true
    }
}
