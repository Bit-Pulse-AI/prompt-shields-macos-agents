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
                    configureAppAppearance()
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
}
