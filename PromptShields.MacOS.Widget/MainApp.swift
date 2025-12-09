import SwiftUI
import Combine
import SwiftData
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

@main
// swiftlint:disable:next type_name
struct MainApp: App {
    @StateObject private var accessibilityManager = AccessibilityManagerImpl()
    @StateObject private var overlayStateModel = OverlayStateModel()
    @StateObject private var dashboardStateModel = DashboardStateModel()
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static let overlayRender = "overlay-render"
    static let actionRender = "action-render"
    static let mainWindow = "main-window"

    // Minimum size that doesn't cause constraint issues on macOS Sequoia
    private static let minWindowSize = CGSize(width: 50, height: 50)

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "MainApp"
    )

    var body: some Scene {
        Window("Main", id: MainApp.mainWindow) {
            MainWindowContent()
                .environmentObject(accessibilityManager)
                .environmentObject(overlayStateModel)
                .environmentObject(dashboardStateModel)
                .task {
                    await initializeMainWindow()
                }
        }
        .defaultSize(width: MainApp.minWindowSize.width, height: MainApp.minWindowSize.height)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .environmentObject(dashboardStateModel)
        .windowStyle(.hiddenTitleBar)

        Window("Overlay Render", id: MainApp.overlayRender) {
            OverlayWindowContent()
                .environmentObject(accessibilityManager)
                .environmentObject(overlayStateModel)
        }
        .defaultSize(width: MainApp.minWindowSize.width, height: MainApp.minWindowSize.height)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)

        Window("Action", id: MainApp.actionRender) {
            ActionWindowContent()
                .environmentObject(accessibilityManager)
                .environmentObject(overlayStateModel)
        }
        .defaultSize(width: MainApp.minWindowSize.width, height: MainApp.minWindowSize.height)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)
    }

    @MainActor
    private func initializeMainWindow() async {
        // Wait for the next run loop iteration to ensure window is created
        try? await Task.sleep(for: .milliseconds(100))

        configureAppAppearance()
        setupWindowDelegate()

        // Configure windows after a delay to avoid constraint conflicts
        try? await Task.sleep(for: .milliseconds(200))

        updateMainWindow(isInitial: true)
        updateOverlayWindow(isInitial: true)
        updateActionWindow(isInitial: true)
    }

    private func updateMainWindow(isInitial: Bool) {
        let targetFrame = overlayStateModel.elementInfo?.frame

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.mainWindow) ?? false }) {
            configureMainWindow(isInitial: isInitial, window: window, targetRect: targetFrame)
            overlayStateModel.isMainConfigured = true
        }
    }

    private func updateOverlayWindow(isInitial: Bool) {
        if overlayStateModel.elementInfo?.frame == nil {
            overlayStateModel.actionToolState = .idle
        }
        let targetFrame = overlayStateModel.elementInfo?.frame

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.overlayRender) ?? false }) {
            configureOverlayWindow(isInitial: isInitial, window: window, targetRect: targetFrame)
            overlayStateModel.isOverlayConfigured = true
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
            window.orderFrontRegardless()
        } else {
            // Hide window off-screen when no target
            window.setFrame(CGRect(x: -10000, y: -10000, width: MainApp.minWindowSize.width, height: MainApp.minWindowSize.height), display: false, animate: false)
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
        window.ignoresMouseEvents = true

        if let targetRect = targetRect {
            let targetTransform = CGRect(
                x: targetRect.origin.x,
                y: targetRect.origin.y - targetRect.height,
                width: max(targetRect.width, MainApp.minWindowSize.width),
                height: max(targetRect.height, MainApp.minWindowSize.height)
            )
            window.setFrame(targetTransform, display: true, animate: false)
            window.alphaValue = 1.0
            window.orderFrontRegardless()
        } else {
            // Hide window off-screen when no target
            window.setFrame(CGRect(x: -10000, y: -10000, width: MainApp.minWindowSize.width, height: MainApp.minWindowSize.height), display: false, animate: false)
            window.alphaValue = 0.0
        }
    }

    private func configureAppAppearance() {
        // Open windows sequentially with delays to avoid constraint conflicts on Sequoia
        openWindow(id: MainApp.mainWindow)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [openWindow] in
            openWindow(id: MainApp.overlayRender)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [openWindow] in
            openWindow(id: MainApp.actionRender)
        }

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

// MARK: - Window Content Views

/// Main window content that handles its own updates
private struct MainWindowContent: View {
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    var body: some View {
        Group {
            if overlayStateModel.isMainConfigured {
                MainView()
            } else {
                // Placeholder with valid minimum size to prevent constraint issues
                Color.clear
                    .frame(minWidth: 50, minHeight: 50)
            }
        }
        .onReceive(accessibilityManager.$elementInfo) { newValue in
            guard overlayStateModel.isMainConfigured else { return }
            overlayStateModel.elementInfo = newValue
        }
    }
}

/// Overlay window content that handles its own updates
private struct OverlayWindowContent: View {
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    var body: some View {
        Group {
            if overlayStateModel.isOverlayConfigured {
                OverlayView()
            } else {
                // Placeholder with valid minimum size to prevent constraint issues
                Color.clear
                    .frame(minWidth: 50, minHeight: 50)
            }
        }
        .onReceive(accessibilityManager.$elementInfo) { newValue in
            guard overlayStateModel.isOverlayConfigured else { return }
            overlayStateModel.elementInfo = newValue
            if newValue?.frame == nil {
                overlayStateModel.actionToolState = .idle
            }
            updateOverlayWindowPosition()
        }
        .onChange(of: overlayStateModel.actionToolState) { _, _ in
            guard overlayStateModel.isOverlayConfigured else { return }
            updateOverlayWindowPosition()
        }
    }

    private func updateOverlayWindowPosition() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.overlayRender) ?? false }) else {
            return
        }

        if let targetRect = overlayStateModel.elementInfo?.frame {
            let targetTransform = CGRect(
                x: targetRect.origin.x,
                y: targetRect.origin.y - targetRect.height,
                width: max(targetRect.width, 50),
                height: max(targetRect.height, 50)
            )
            window.setFrame(targetTransform, display: true, animate: false)
            window.alphaValue = 1.0
            window.orderFrontRegardless()
        } else {
            window.setFrame(CGRect(x: -10000, y: -10000, width: 50, height: 50), display: false, animate: false)
            window.alphaValue = 0.0
        }
    }
}

/// Action window content that handles its own updates
private struct ActionWindowContent: View {
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    var body: some View {
        Group {
            if overlayStateModel.isActionConfigured {
                ActionView()
            } else {
                // Placeholder with valid minimum size to prevent constraint issues
                Color.clear
                    .frame(minWidth: 50, minHeight: 50)
            }
        }
        .onReceive(accessibilityManager.$elementInfo) { newValue in
            guard overlayStateModel.isActionConfigured else { return }
            overlayStateModel.elementInfo = newValue
            updateActionWindowPosition()
        }
        .onChange(of: overlayStateModel.actionToolState) { _, _ in
            guard overlayStateModel.isActionConfigured else { return }
            updateActionWindowPosition()
        }
    }

    private func updateActionWindowPosition() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.actionRender) ?? false }) else {
            return
        }

        var actionSize: CGSize
        switch overlayStateModel.actionToolState {
        case .idle, .loading:
            actionSize = CGSize(width: 50, height: 50)
        case .options, .category:
            actionSize = CGSize(width: 200, height: 100)
        case .action:
            actionSize = CGSize(width: 200, height: 200)
        }

        if let targetRect = overlayStateModel.elementInfo?.frame {
            let targetTransform = CGRect(
                x: targetRect.origin.x,
                y: targetRect.origin.y,
                width: actionSize.width,
                height: actionSize.height
            )
            window.setFrame(targetTransform, display: true, animate: false)
            window.alphaValue = 1.0
            window.orderFrontRegardless()
        } else {
            window.setFrame(CGRect(x: -10000, y: -10000, width: 50, height: 50), display: false, animate: false)
            window.alphaValue = 0.0
        }
    }
}
