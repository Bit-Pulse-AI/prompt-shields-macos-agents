import SwiftUI

struct FloatingToolView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    private var frame: CGRect? {
        overlayStateModel.elementInfo?.frame
    }
    var body: some View {
        ZStack {
            VStack {
            }
            .frame(width: frame?.width ?? 0, height: frame?.height ?? 0)
            .background(Color.black.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white, lineWidth: 1)
                )
            .frame(width: 0, height: 0)
            .onAppear {
                updateWindows()
            }
        }
        .onChange(of: frame) { _, _ in
            updateWindows()
        }
        .onChange(of: overlayStateModel.actionToolState) { _, _ in
            updateWindows()
        }
    }
    
    private func updateWindows() {
        if overlayStateModel.elementInfo?.frame == nil {
            overlayStateModel.actionToolState = .idle
        }
        let targetFrame = overlayStateModel.elementInfo?.frame
        let actionToolState = overlayStateModel.actionToolState
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == MainApp.overlayRender }) {
            configureOverlayWindow(window, targetRect: targetFrame)
        }
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == MainApp.actionRender }) {
            var actionSize: CGSize
            
            switch actionToolState {
            case .idle:
                actionSize = CGSize(width: 50, height: 50)
            case .loading:
                actionSize = CGSize(width: 50, height: 50)
            case .options:
                actionSize = CGSize(width: 200, height: 200)
            }
            configureActionWindow(window, targetRect: targetFrame, actionSize: actionSize)
        }
    }
    @MainActor
    private func configureActionWindow(_ window: NSWindow, targetRect: CGRect?, actionSize: CGSize) {
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
            window.setFrame(.zero, display: true, animate: false)
        }
        // Force window to become key for text input
        window.makeKeyAndOrderFront(nil)
    }
    
    @MainActor
    private func configureOverlayWindow(_ window: NSWindow, targetRect: CGRect?) {
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
            window.setFrame(.zero, display: true, animate: false)
        }
    }
}
