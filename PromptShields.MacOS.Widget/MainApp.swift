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

    // Proper size for main dashboard window
    private static let mainWindowSize = CGSize(width: 900, height: 600)

    // Minimum size for utility windows to avoid constraint issues on Sequoia
    private static let utilityWindowMinSize = CGSize(width: 50, height: 50)

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
                    await initializeWindows()
                }
        }
        .defaultSize(width: MainApp.mainWindowSize.width, height: MainApp.mainWindowSize.height)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .environmentObject(dashboardStateModel)
        .windowStyle(.hiddenTitleBar)

        Window("Overlay Render", id: MainApp.overlayRender) {
            OverlayWindowContent()
                .environmentObject(accessibilityManager)
                .environmentObject(overlayStateModel)
        }
        .defaultSize(width: MainApp.utilityWindowMinSize.width, height: MainApp.utilityWindowMinSize.height)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)

        Window("Action", id: MainApp.actionRender) {
            ActionWindowContent()
                .environmentObject(accessibilityManager)
                .environmentObject(overlayStateModel)
        }
        .defaultSize(width: MainApp.utilityWindowMinSize.width, height: MainApp.utilityWindowMinSize.height)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)
    }

    @MainActor
    private func initializeWindows() async {
        // Wait for windows to be created
        try? await Task.sleep(for: .milliseconds(100))

        configureAppAppearance()
        setupWindowDelegate()

        // Configure windows after a delay to avoid constraint conflicts
        try? await Task.sleep(for: .milliseconds(200))

        configureMainWindow()
        configureOverlayWindow()
        configureActionWindow()

        // Mark windows as configured
        overlayStateModel.isMainConfigured = true
        overlayStateModel.isOverlayConfigured = true
        overlayStateModel.isActionConfigured = true
    }

    @MainActor
    private func configureMainWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.mainWindow) ?? false }) else {
            return
        }

        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.isOpaque = true
        window.backgroundColor = .white
        window.level = .modalPanel
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false

        // Set proper size for main window
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowSize = MainApp.mainWindowSize
        let windowOrigin = CGPoint(
            x: (screenFrame.width - windowSize.width) / 2 + screenFrame.origin.x,
            y: (screenFrame.height - windowSize.height) / 2 + screenFrame.origin.y
        )
        window.setFrame(CGRect(origin: windowOrigin, size: windowSize), display: true)
    }

    @MainActor
    private func configureOverlayWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.overlayRender) ?? false }) else {
            logger.warning("Overlay window not found")
            return
        }

        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false

        if window.styleMask.contains(.titled) {
            window.styleMask.remove(.titled)
        }

        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = true

        // Start off-screen
        window.setFrame(CGRect(x: -10000, y: -10000, width: 50, height: 50), display: false)
        window.alphaValue = 0.0
    }

    @MainActor
    private func configureActionWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.actionRender) ?? false }) else {
            logger.warning("Action window not found")
            return
        }

        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false

        if window.styleMask.contains(.titled) {
            window.styleMask.remove(.titled)
        }

        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false

        // Start off-screen
        window.setFrame(CGRect(x: -10000, y: -10000, width: 50, height: 50), display: false)
        window.alphaValue = 0.0
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

/// Main window content
private struct MainWindowContent: View {
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    var body: some View {
        Group {
            if overlayStateModel.isMainConfigured {
                MainView()
            } else {
                // Loading placeholder with proper size
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(accessibilityManager.$elementInfo) { newValue in
            guard overlayStateModel.isMainConfigured else { return }
            overlayStateModel.elementInfo = newValue
        }
    }
}

/// Overlay window content
private struct OverlayWindowContent: View {
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    var body: some View {
        Group {
            if overlayStateModel.isOverlayConfigured {
                OverlayView()
            } else {
                Color.clear
                    .frame(width: 50, height: 50)
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

/// Action window content that scales with its content
private struct ActionWindowContent: View {
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    var body: some View {
        Group {
            if overlayStateModel.isActionConfigured {
                ActionView()
                    .fixedSize() // Allow the view to size to its content
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onChange(of: geometry.size) { _, newSize in
                                    updateActionWindowSize(to: newSize)
                                }
                                .onAppear {
                                    // Initial size update
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        updateActionWindowSize(to: geometry.size)
                                    }
                                }
                        }
                    )
            } else {
                Color.clear
                    .frame(width: 50, height: 50)
            }
        }
        .onReceive(accessibilityManager.$elementInfo) { newValue in
            guard overlayStateModel.isActionConfigured else { return }
            overlayStateModel.elementInfo = newValue
            updateActionWindowPosition()
        }
        .onChange(of: overlayStateModel.actionToolState) { _, _ in
            guard overlayStateModel.isActionConfigured else { return }
            // Delay position update to allow content size to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                updateActionWindowPosition()
            }
        }
    }

    private func updateActionWindowSize(to size: CGSize) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.actionRender) ?? false }),
              size.width > 0, size.height > 0 else {
            return
        }

        // Only resize if we have a valid target position
        if let targetRect = overlayStateModel.elementInfo?.frame {
            let proposedFrame = CGRect(
                x: targetRect.origin.x,
                y: targetRect.origin.y,
                width: max(size.width, 50),
                height: max(size.height, 50)
            )
            let adjustedFrame = adjustFrameToVisibleScreen(proposedFrame)
            window.setFrame(adjustedFrame, display: true, animate: false)
        }
    }

    private func updateActionWindowPosition() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.actionRender) ?? false }) else {
            return
        }

        if let targetRect = overlayStateModel.elementInfo?.frame {
            // Use the window's current content size or a minimum
            let currentSize = window.frame.size
            let width = max(currentSize.width, 50)
            let height = max(currentSize.height, 50)

            let proposedFrame = CGRect(
                x: targetRect.origin.x,
                y: targetRect.origin.y,
                width: width,
                height: height
            )
            let adjustedFrame = adjustFrameToVisibleScreen(proposedFrame)
            window.setFrame(adjustedFrame, display: true, animate: false)
            window.alphaValue = 1.0
            window.orderFrontRegardless()
        } else {
            window.setFrame(CGRect(x: -10000, y: -10000, width: 50, height: 50), display: false, animate: false)
            window.alphaValue = 0.0
        }
    }

    /// Adjusts a proposed frame to ensure it stays within the visible screen bounds
    /// - Parameter frame: The proposed window frame
    /// - Returns: An adjusted frame that fits within the visible screen area
    private func adjustFrameToVisibleScreen(_ frame: CGRect) -> CGRect {
        // Get the screen containing the proposed frame, or fall back to main screen
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return frame
        }

        var adjustedFrame = frame
        let padding: CGFloat = 10 // Keep some padding from screen edges

        // Adjust horizontal position
        // If window extends beyond right edge, move it left
        if adjustedFrame.maxX > visibleFrame.maxX - padding {
            adjustedFrame.origin.x = visibleFrame.maxX - adjustedFrame.width - padding
        }
        // If window extends beyond left edge, move it right
        if adjustedFrame.minX < visibleFrame.minX + padding {
            adjustedFrame.origin.x = visibleFrame.minX + padding
        }

        // Adjust vertical position
        // If window extends beyond top edge, move it down
        if adjustedFrame.maxY > visibleFrame.maxY - padding {
            adjustedFrame.origin.y = visibleFrame.maxY - adjustedFrame.height - padding
        }
        // If window extends beyond bottom edge, move it up
        if adjustedFrame.minY < visibleFrame.minY + padding {
            adjustedFrame.origin.y = visibleFrame.minY + padding
        }

        // Ensure minimum position values are valid
        adjustedFrame.origin.x = max(adjustedFrame.origin.x, visibleFrame.minX + padding)
        adjustedFrame.origin.y = max(adjustedFrame.origin.y, visibleFrame.minY + padding)

        // If the window is larger than the screen, constrain it
        if adjustedFrame.width > visibleFrame.width - (padding * 2) {
            adjustedFrame.size.width = visibleFrame.width - (padding * 2)
            adjustedFrame.origin.x = visibleFrame.minX + padding
        }
        if adjustedFrame.height > visibleFrame.height - (padding * 2) {
            adjustedFrame.size.height = visibleFrame.height - (padding * 2)
            adjustedFrame.origin.y = visibleFrame.minY + padding
        }

        return adjustedFrame
    }
}
