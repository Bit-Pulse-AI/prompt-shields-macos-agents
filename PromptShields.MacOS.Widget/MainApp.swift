import SwiftUI
import Combine
import SwiftData

final class OverlayStateModel: ObservableObject {
    @Published var floatingWindowRect = CGRect.zero
}

// swiftlint:disable:next type_name
@main
struct MainApp: App {
    // MARK: - Properties
    
    @StateObject private var overlayStateModel = OverlayStateModel()
    @Environment(\.openWindow) private var openWindow
    /// Application delegate for handling app lifecycle events
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainView(overlayStateObject: _overlayStateModel)
                .onAppear {
                    configureAppAppearance()
                }
        }
        .windowStyle(.hiddenTitleBar)
        // Floating tool window with a unique ID
        Window("Overlay Render", id: "overlay-render") {
            ZStack(alignment: .leading) {
                FloatingToolView(desiredFrameInScreenCoords: $overlayStateModel.floatingWindowRect)
                    .frame(width: overlayStateModel.floatingWindowRect.width, height: overlayStateModel.floatingWindowRect.height)
                    .background(Color.clear)
                Button {
                    print("test")
                } label: {
                    Image(ImageResource(name: "logo_mid", bundle: .main))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 30)
                }.position(.zero).offset(x: overlayStateModel.floatingWindowRect.width, y: 15)
            }.frame(alignment: .top)
        }
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)
    }
    
    /// Configures the application appearance settings
    private func configureAppAppearance() {
        openWindow(id: "overlay-render")
        NSApp.appearance = NSAppearance(named: .aqua)
    }
}

/// Example floating transparent SwiftUI view that positions the window reliably.
struct FloatingToolView: View {
    /// The rect we want the window to occupy, in screen coordinates (origin = bottom-left)
    @Binding var desiredFrameInScreenCoords: CGRect

    @State private var configured = false

    var body: some View {
        ZStack {
            VStack {
            }
            .frame(width: desiredFrameInScreenCoords.width, height: desiredFrameInScreenCoords.height)
            .background(Color.clear)
            .cornerRadius(8)
            // Invisible accessor to get the NSWindow for this SwiftUI view.
            WindowAccessor { window in
                guard let window = window, !configured else { return }
                configured = true
                configureWindow(window, targetRect: desiredFrameInScreenCoords)
            }
            .frame(width: 0, height: 0)
        }
        .onChange(of: desiredFrameInScreenCoords) { _, newRect in
            if let window = NSApp.windows.first(where: { $0.title == "Overlay Render" }) {
                configureWindow(window, targetRect: newRect)
            }
        }
    }

    /// Configure appearance and position.
    @MainActor
    private func configureWindow(_ window: NSWindow, targetRect: CGRect) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        
        window.styleMask.remove(.titled)
        window.styleMask.remove(.closable)
        window.styleMask.remove(.miniaturizable)
        window.styleMask.remove(.resizable)

        window.ignoresMouseEvents = true
        window.isMovableByWindowBackground = true
        let targetTransform = CGRect(x: targetRect.origin.x, y: targetRect.origin.y, width: fmax(targetRect.size.width, 32), height: fmax(targetRect.size.height, 32))
        window.setFrame(targetTransform, display: true, animate: false)
    }
}

/// A tiny NSViewRepresentable that gives you the NSWindow for the hosting view.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Kick the callback asynchronously so the view has a window when possible.
        DispatchQueue.main.async { [weak view] in
            onWindow(view?.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            onWindow(nsView?.window)
        }
    }
}
