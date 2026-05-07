import SwiftUI
import Combine
import SwiftData
import os

enum ActionToolState: Equatable {
    case idle
    case loading
    case action
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

    /// AI-SPM policy enforcer. `nil` for tenants without a configured
    /// dashboard URL — Promptly falls back to local-only heuristics.
    /// Wired up at app boot via `MainApp.configurePolicyClient`.
    /// Both properties are MainActor-only at the call sites; this class
    /// stays non-isolated to keep Swift 6 concurrency happy with existing
    /// SwiftUI usage.
    @MainActor var policyClient: PolicyClient?
    @MainActor var policyEnforcer: PolicyEnforcer?
}

@main
// swiftlint:disable:next type_name
struct MainApp: App {
    @StateObject private var accessibilityManager = AccessibilityManagerImpl()
    @StateObject private var overlayStateModel = OverlayStateModel()
    @StateObject private var dashboardStateModel = DashboardStateModel()
    @StateObject private var chatStateModel = ChatStateModel()
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static let overlayRender = "overlay-render"
    static let actionRender = "action-render"
    static let mainWindow = "main-window"
    static let chatWindow = "chat-window"

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
                .environmentObject(chatStateModel)
                .task {
                    await initializeWindows()
                }
        }
        .defaultSize(width: MainApp.mainWindowSize.width, height: MainApp.mainWindowSize.height)
        .environmentObject(accessibilityManager)
        .environmentObject(overlayStateModel)
        .environmentObject(dashboardStateModel)
        .environmentObject(chatStateModel)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .help) {
                Button("Show Onboarding…") {
                    NotificationCenter.default.post(name: .showOnboarding, object: nil)
                }
                Button("Toggle Promptly Chat") {
                    chatStateModel.isExpanded.toggle()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                #if DEBUG
                // Dev-only: bypass Auth0 entirely so QA can click through
                // the dashboard without real credentials. Downstream user-
                // dependent screens (Account, Suggestions) will be empty
                // because no real user is loaded — that's expected.
                Divider()
                Button("Skip Login (Dev)") {
                    NotificationCenter.default.post(name: .devSkipLogin, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                #endif
            }
        }

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

        // Floating Chat — Grammarly-style persistent button anchored to
        // the bottom-right of the active screen. Click expands to the
        // ChatPanelView. Window is `.statusBar`-level so it floats above
        // everything except the menu bar / system overlays.
        Window("Promptly Chat", id: MainApp.chatWindow) {
            FloatingChatButton()
                .environmentObject(chatStateModel)
                .environmentObject(overlayStateModel)
        }
        .defaultSize(width: 420, height: 580)
        .environmentObject(chatStateModel)
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
        configureChatWindow()
        configurePolicyClient()

        // Mark windows as configured
        overlayStateModel.isMainConfigured = true
        overlayStateModel.isOverlayConfigured = true
        overlayStateModel.isActionConfigured = true
    }

    /// Wire up the AI-SPM policy client. Tenants without a dashboard URL
    /// configured get a `NullPolicyTransport` — PolicyEnforcer always
    /// returns `.allow`, no network calls happen, and Promptly behaves
    /// exactly like before.
    @MainActor
    private func configurePolicyClient() {
        // Dashboard URL is read from UserDefaults so QA can override
        // without rebuilding. Production builds set it via the gitignored
        // `Resources/<env>/Const.swift` (see policy-integration.md). For
        // now we accept either source; absent both, fall back to NullTransport.
        let urlString = UserDefaults.standard.string(
            forKey: "ai.bit-pulse.promptshields.aiSPMDashboardURL"
        ) ?? ""

        let transport: PolicyTransport
        if !urlString.isEmpty, let url = URL(string: urlString) {
            transport = HTTPPolicyTransport(baseURL: url)
        } else {
            transport = NullPolicyTransport()
        }

        let client = PolicyClient(transport: transport)
        let enforcer = PolicyEnforcer(client: client)
        overlayStateModel.policyClient = client
        overlayStateModel.policyEnforcer = enforcer
        client.start()

        // Telemetry stream (people / auto-discovery / usage rollup) shares
        // the same dashboard URL — keep both wired in lockstep so a tenant
        // either gets all SPM telemetry or none.
        let telemetryTransport: TelemetryTransport
        if !urlString.isEmpty, let url = URL(string: urlString) {
            telemetryTransport = HTTPTelemetryTransport(baseURL: url)
        } else {
            telemetryTransport = NullTelemetryTransport()
        }
        TelemetryClient.shared.setTransport(telemetryTransport)
        UsageEventAggregator.shared.start()
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
        window.level = .normal
        window.hasShadow = true
        // PS-15: Main window must live on a single Space, like a standard macOS app.
        // Overlay/Action windows still join all Spaces so they can track focused text fields.
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.isMovableByWindowBackground = false

        // PS-09: enforce minimum window size (800x560) for breathing room.
        window.minSize = NSSize(width: 800, height: 560)

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
            logger.debug("Overlay window not found")
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
            logger.debug("Action window not found")
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

    /// Floating Chat window — sits at bottom-right of the active screen,
    /// always visible (.statusBar level). The button sizes itself; the
    /// expanded panel needs more room — we resize on demand from the view
    /// via .onChange(of: chat.isExpanded), so here we just position.
    @MainActor
    private func configureChatWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(MainApp.chatWindow) ?? false }) else {
            logger.debug("Chat window not found")
            return
        }

        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.titlebarAppearsTransparent = true

        if window.styleMask.contains(.titled) {
            window.styleMask.remove(.titled)
        }
        window.styleMask.insert(.borderless)

        // Sit above normal app windows (panels, modals) but below the
        // menu bar / dock. statusBar is the right level for an always-on
        // floating widget.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = false

        // Anchor to bottom-right of the main screen with a comfortable margin.
        // The view inside is sized to its content so the window auto-fits.
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let panelMargin: CGFloat = 24
            let panelSize = CGSize(width: 420, height: 580)
            let origin = CGPoint(
                x: visible.maxX - panelSize.width - panelMargin,
                y: visible.minY + panelMargin
            )
            window.setFrame(CGRect(origin: origin, size: panelSize), display: true)
        }
    }

    private func configureAppAppearance() {
        // Open windows sequentially with delays to avoid constraint conflicts on Sequoia
        openWindow(id: MainApp.mainWindow)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [openWindow] in
            openWindow(id: MainApp.overlayRender)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [openWindow] in
            openWindow(id: MainApp.chatWindow)
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
        // Onboarding sheet presentation lives inside MainView so it has
        // direct access to the global MainStateModel — the merged step 4
        // performs the Auth0 login and needs to mutate authState on success.
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("ai.bit-pulse.promptshields.showOnboarding")

    /// Posted by Help menu → "Skip Login (Dev)" in DEBUG builds.
    /// MainView listens and synthesises a logged-in state for click-through QA
    /// without needing real Auth0 credentials.
    static let devSkipLogin = Notification.Name("ai.bit-pulse.promptshields.devSkipLogin")
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
                width: targetRect.width,
                height: targetRect.height
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
