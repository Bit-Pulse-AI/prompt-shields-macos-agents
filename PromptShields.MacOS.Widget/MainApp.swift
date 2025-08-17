import SwiftUI
import Combine
import SwiftData
import AppKit
import os

enum ActionToolState {
    case idle
    case loading
    case options
}
final class OverlayStateModel: ObservableObject {
    @Published var elementInfo: ElementInfo?
    @Published var actionToolState: ActionToolState = .idle
    @Published var promptText: String = ""
    @Published var textFieldHeight: CGFloat = 40
}

// swiftlint:disable:next type_name
@main
struct MainApp: App {
    enum Field: Hashable {
        case textField
    }
    
    // MARK: - Properties
    @StateObject private var overlayStateModel = OverlayStateModel()
    @Environment(\.openWindow) private var openWindow
    /// Application delegate for handling app lifecycle events
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    static let overlayRender = "overlay-render"
    static let actionRender = "action-render"
    static let mainWindow = "main-window"
    
    var body: some Scene {
        WindowGroup("Main", id: MainApp.mainWindow) {
            MainView(overlayStateObject: _overlayStateModel)
                .onAppear {
                    cleanupHangingWindows()
                    configureAppAppearance()
                    // Temporarily disable window delegate setup
                     setupWindowDelegate()
                }
        }
        .windowStyle(.hiddenTitleBar)
        
        Window("Overlay Render", id: MainApp.overlayRender) {
            OverlayView()
        }
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)
        Window("Action", id: MainApp.actionRender) {
            ActionView()
        }
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)
    }
    
    /// Configures the application appearance settings
    private func configureAppAppearance() {
        openWindow(id: "overlay-render")
        openWindow(id: "action-render")
        NSApp.appearance = NSAppearance(named: .aqua)
    }
    
    /// Sets up the window delegate to handle window closing behavior
    private func setupWindowDelegate() {
        // Try to find the main window and set its delegate with a longer delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let mainWindow = NSApp.windows.first(where: { 
                $0.identifier?.rawValue == MainApp.mainWindow 
            }) {
                // Only set delegate if it's not already set
                if mainWindow.delegate == nil {
                    mainWindow.delegate = NSApp.delegate as? NSWindowDelegate
                }
            }
        }
    }
    
    /// Cleans up any hanging windows from previous app runs
    private func cleanupHangingWindows() {
        // Get all existing windows
        let existingWindows = NSApp.windows
        
        // Close any windows that match our known identifiers
        let windowIdentifiers = [MainApp.mainWindow, MainApp.overlayRender, MainApp.actionRender]
        
        for window in existingWindows {
            if let identifier = window.identifier?.rawValue,
               windowIdentifiers.contains(identifier) {
                print("Cleaning up hanging window with identifier: \(identifier)")
                window.close()
            }
        }
    }
}
