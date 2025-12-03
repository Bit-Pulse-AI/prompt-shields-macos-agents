import SwiftUI
import Combine
import SwiftData
import AppKit
import os

enum ActionToolState: Equatable {
    case idle
    case loading
    case action
    case options(String)
    case category
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
    @StateObject private var accessibilityManager = AccessibilityManagerImpl()
    @StateObject private var overlayStateModel = OverlayStateModel()
    @StateObject private var dashboardStateModel = DashboardStateModel()

    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static let overlayRender = "overlay-render"
    static let actionRender = "action-render"
    static let mainWindow = "main-window"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "MainApp"
    )

    var body: some Scene {
        Window("Main", id: MainApp.mainWindow) {
            if $overlayStateModel.isMainConfigured.wrappedValue {
                MainView()
                    .onReceive(accessibilityManager.$elementInfo) { newValue in
                        overlayStateModel.elementInfo = newValue
                        updateMainWindow(isInitial: false)
                    }
                    .onChange(of: overlayStateModel.actionToolState) { _, _ in
                        updateMainWindow(isInitial: false)
                    }
            } else {
                // Use a minimal but non-zero size to ensure the window is created
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        configureAppAppearance()
                        setupWindowDelegate()
                        updateMainWindow(isInitial: true)
                    }
            }
        }
        .defaultSize(width: 1, height: 1)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .environmentObject(dashboardStateModel)
        .windowStyle(.hiddenTitleBar)

        Window("Overlay Render", id: MainApp.overlayRender) {
            if $overlayStateModel.isOverlayConfigured.wrappedValue {
                OverlayView()
                    .onReceive(accessibilityManager.$elementInfo) { newValue in
                        overlayStateModel.elementInfo = newValue
                        updateOverlayWindow(isInitial: false)
                    }
                    .onChange(of: overlayStateModel.actionToolState) { _, _ in
                        updateOverlayWindow(isInitial: false)
                    }
            } else {
                // Use a minimal but non-zero size to ensure the window is created
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        updateOverlayWindow(isInitial: true)
                    }
            }
        }
        .defaultSize(width: 1, height: 1)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)

        Window("Action", id: MainApp.actionRender) {
            if $overlayStateModel.isActionConfigured.wrappedValue {
                ActionView()
                    .onReceive(accessibilityManager.$elementInfo) { newValue in
                        overlayStateModel.elementInfo = newValue
                        updateActionWindow(isInitial: false)
                    }
                    .onChange(of: overlayStateModel.actionToolState) { _, _ in
                        updateActionWindow(isInitial: false)
                    }
            } else {
                // Use a minimal but non-zero size to ensure the window is created
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        updateActionWindow(isInitial: true)
                    }
            }
        }
        .defaultSize(width: 1, height: 1)
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
            case .options, .category:
                actionSize = CGSize(width: 200, height: 100)
            case .action:
                actionSize = CGSize(width: 200, height: 200)
            }

            configureActionWindow(isInitial: isInitial, window: window, targetRect: targetFrame, actionSize: actionSize)
            overlayStateModel.isActionConfigured = true
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
            logger.warning("Action window is nil")
            return
        }

        // Basic window configuration
        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false

        // Remove title bar if present
        if window.styleMask.contains(.titled) {
            window.styleMask.remove(.titled)
        }

        // Set window level - use screenSaver level to ensure visibility above other apps
        window.level = .screenSaver

        // Allow window to appear on all spaces
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false

        if let targetRect = targetRect {
            let targetTransform = CGRect(
                x: targetRect.origin.x,
                y: targetRect.origin.y,
                width: actionSize.width,
                height: actionSize.height
            )
            window.setFrame(targetTransform, display: true, animate: false)
            window.alphaValue = 1.0
            window.orderFrontRegardless() // Force window to front regardless of app activation state
            // logger.debug("Action window positioned at: \(targetTransform)")
        } else {
            // Hide window off-screen when no target
            window.setFrame(CGRect(x: -10000, y: -10000, width: 1, height: 1), display: false, animate: false)
            window.alphaValue = 0.0
        }
    }

    @MainActor
    private func configureOverlayWindow(isInitial: Bool, window: NSWindow?, targetRect: CGRect?) {
        guard let window else {
            logger.warning("Overlay window is nil")
            return
        }

        // Basic window configuration
        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false

        // Remove title bar if present
        if window.styleMask.contains(.titled) {
            window.styleMask.remove(.titled)
        }

        // Set window level - use screenSaver level to ensure visibility above other apps
        window.level = .screenSaver

        // Allow window to appear on all spaces
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = true // Overlay should not capture mouse events

        if let targetRect = targetRect {
            let targetTransform = CGRect(
                x: targetRect.origin.x,
                y: targetRect.origin.y - targetRect.height,
                width: max(targetRect.width, 1),
                height: max(targetRect.height, 1)
            )
            window.setFrame(targetTransform, display: true, animate: false)
            window.alphaValue = 1.0
            window.orderFrontRegardless() // Force window to front regardless of app activation state
            // logger.debug("Overlay window positioned at: \(targetTransform)")
        } else {
            // Hide window off-screen when no target
            window.setFrame(CGRect(x: -10000, y: -10000, width: 1, height: 1), display: false, animate: false)
            window.alphaValue = 0.0
        }
    }

    private func configureAppAppearance() {
        openWindow(id: MainApp.mainWindow)
        openWindow(id: MainApp.overlayRender)
        openWindow(id: MainApp.actionRender)
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    private func setupWindowDelegate() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let mainWindow = NSApp.windows.first(where: {
                $0.identifier?.rawValue.hasPrefix(MainApp.mainWindow) ?? false
            }) {
                if mainWindow.delegate == nil {
                    mainWindow.delegate = NSApp.delegate as? NSWindowDelegate
                }
            }
        }
    }
}
