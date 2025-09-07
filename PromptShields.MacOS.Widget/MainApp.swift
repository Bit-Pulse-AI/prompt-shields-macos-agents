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

enum ResultAction {
    case inject(String)
}
final class OverlayStateModel: ObservableObject {
    @Published var elementInfo: ElementInfo?
    @Published var actionToolState: ActionToolState = .idle
    @Published var resultAction: ResultAction?
    @Published var isMainConfigured: Bool = false
    @Published var isOverlayConfigured: Bool = false
    @Published var isActionConfigured: Bool = false
}

// swiftlint:disable:next type_name
@main
struct MainApp: App {
    @StateObject private var accessibilityManager: AccessibilityManagerImpl
    @StateObject private var overlayStateModel: OverlayStateModel
    @StateObject private var dashboardStateModel: DashboardStateModel
    
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    static let overlayRender = "overlay-render"
    static let actionRender = "action-render"
    static let mainWindow = "main-window"
    
    init() {
        let overlayStateModel = OverlayStateModel()
        let dashboardStateModel = DashboardStateModel()
        let elementInfoBinding = Binding(get: {
            return overlayStateModel.elementInfo
        }, set: { newValue in
            Task { @MainActor in
                overlayStateModel.elementInfo = newValue
            }
        })
        let applicationInfoBinding = Binding(get: {
            return dashboardStateModel.currentApplication
        }, set: { newValue in
            Task { @MainActor in
                dashboardStateModel.currentApplication = newValue
            }
        })
        let isActive = Binding(get: {
            return dashboardStateModel.isActive
        }, set: { newValue in
            Task { @MainActor in
                dashboardStateModel.isActive = newValue
            }
        })
        let accessibilityManager = AccessibilityManagerImpl(elementInfo: elementInfoBinding,
                                                            applicationInfo: applicationInfoBinding,
                                                            isActive: isActive)
        self._accessibilityManager = StateObject(wrappedValue: accessibilityManager)
        self._overlayStateModel = StateObject(wrappedValue: overlayStateModel)
        self._dashboardStateModel = StateObject(wrappedValue: dashboardStateModel)
    }
    
    var body: some Scene {
        Window("Main", id: MainApp.mainWindow) {
//            if $overlayStateModel.isMainConfigured.wrappedValue {
                MainView()
                    .onChange(of: overlayStateModel.elementInfo?.frame) { _, _ in
                        updateMainWindow(isInitial: false)
                    }
                    .onChange(of: overlayStateModel.actionToolState) { _, _ in
                        updateMainWindow(isInitial: false)
                    }
//            } else {
//                VStack {
//                }
//                .frame(width: 1, height: 1)
                    .onAppear {
                        configureAppAppearance()
                        setupWindowDelegate()
                        updateMainWindow(isInitial: true)
                    }
//            }
        }
        .defaultSize(.zero)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .environmentObject(dashboardStateModel)
        .windowStyle(.hiddenTitleBar)
        Window("Overlay Render", id: MainApp.overlayRender) {
//            if $overlayStateModel.isOverlayConfigured.wrappedValue {
                OverlayView()
                    .onChange(of: overlayStateModel.elementInfo?.frame) { _, _ in
                        updateOverlayWindow(isInitial: false)
                    }
                    .onChange(of: overlayStateModel.actionToolState) { _, _ in
                        updateOverlayWindow(isInitial: false)
                    }
//            } else {
//                VStack {
//                }
//                .frame(width: 1, height: 1)
                .onAppear {
                    updateOverlayWindow(isInitial: true)
                }
//            }
        }
        .defaultSize(.zero)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)
        
        Window("Action", id: MainApp.actionRender) {
            if $overlayStateModel.isActionConfigured.wrappedValue {
                ActionView()
                    .onChange(of: overlayStateModel.elementInfo?.frame) { _, _ in
                        updateActionWindow(isInitial: false)
                    }
                    .onChange(of: overlayStateModel.actionToolState) { _, _ in
                        updateActionWindow(isInitial: false)
                    }
            } else {
                VStack {
                }
                .frame(width: 1, height: 1)
                .onAppear {
                    updateActionWindow(isInitial: true)
                }
            }
        }
        .defaultSize(.zero)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)
    }
     
    private func updateMainWindow(isInitial: Bool) {
        let targetFrame = overlayStateModel.elementInfo?.frame
        
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.mainWindow) ?? false }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
                configureMainWindow(isInitial: isInitial, window: window, targetRect: targetFrame)
                overlayStateModel.isMainConfigured = true
            }
        }
    }
    
    private func updateOverlayWindow(isInitial: Bool) {
        if overlayStateModel.elementInfo?.frame == nil {
            overlayStateModel.actionToolState = .idle
        }
        let targetFrame = overlayStateModel.elementInfo?.frame

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.overlayRender) ?? false }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
                configureOverlayWindow(isInitial: isInitial, window: window, targetRect: targetFrame)
                overlayStateModel.isOverlayConfigured = true
            }
        }
    }
    
    private func updateActionWindow(isInitial: Bool) {
        let targetFrame = overlayStateModel.elementInfo?.frame
        let actionToolState = overlayStateModel.actionToolState
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.actionRender) ?? false }) {
            var actionSize: CGSize
            
            switch actionToolState {
            case .idle:
                actionSize = CGSize(width: 50, height: 50)
            case .loading:
                actionSize = CGSize(width: 50, height: 50)
            case .options:
                actionSize = CGSize(width: 200, height: 100)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
                configureActionWindow(isInitial: isInitial, window: window, targetRect: targetFrame, actionSize: actionSize)
                overlayStateModel.isActionConfigured = true
            }
        }
    }
     
    @MainActor
    private func configureMainWindow(isInitial: Bool, window: NSWindow?, targetRect: CGRect?) {
        guard let window else {
            return
        }
        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.isOpaque = true
        window.backgroundColor = .white
         
        window.level = .modalPanel
        window.hasShadow = false
         
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
    }
     
    @MainActor
    private func configureActionWindow(isInitial: Bool, window: NSWindow?, targetRect: CGRect?, actionSize: CGSize) {
        guard let window else {
            return
        }
        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.isOpaque = false
        window.backgroundColor = .clear
         
        window.level = .floating
        window.hasShadow = false
         
        // Use .titled with .borderless to allow input while keeping borderless appearance
        window.styleMask.remove(.titled)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
         
        if let targetRect = targetRect {
            let targetTransform = CGRect(x: targetRect.origin.x, y: targetRect.origin.y + targetRect.size.height, width: actionSize.width, height: actionSize.height)
            window.setFrame(targetTransform, display: true, animate: false)
        } else {
            window.setFrame(CGRect(x: 0, y: 0, width: 10, height: 10), display: false, animate: false)
        }
    }
     
    @MainActor
    private func configureOverlayWindow(isInitial: Bool, window: NSWindow?, targetRect: CGRect?) {
        guard let window else {
            return
        }
        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
         
        // Use nonactivating panel style for borderless overlay window
        window.styleMask = [.nonactivatingPanel]

        window.ignoresMouseEvents = true
        window.isMovableByWindowBackground = true
        if let targetRect {
            let targetTransform = CGRect(x: targetRect.origin.x, y: targetRect.origin.y, width: targetRect.size.width, height: targetRect.size.height)
            window.setFrame(targetTransform, display: true, animate: false)
        } else {
            window.setFrame(CGRect(x: 0, y: 0, width: 10, height: 10), display: false, animate: false)
        }
    }
    
    /// Configures the application appearance settings
    private func configureAppAppearance() {
        openWindow(id: MainApp.mainWindow)
        openWindow(id: MainApp.overlayRender)
        openWindow(id: MainApp.actionRender)
        NSApp.appearance = NSAppearance(named: .aqua)
    }
    
    /// Sets up the window delegate to handle window closing behavior
    ///
    private func setupWindowDelegate() {
        // Try to find the main window and set its delegate with a longer delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let mainWindow = NSApp.windows.first(where: { 
                $0.identifier?.rawValue.hasPrefix(MainApp.mainWindow) ?? false
            }) {
                // Only set delegate if it's not already set
                if mainWindow.delegate == nil {
                    mainWindow.delegate = NSApp.delegate as? NSWindowDelegate
                }
            }
        }
    }
}
