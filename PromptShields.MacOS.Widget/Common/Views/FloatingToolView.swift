import SwiftUI

struct FloatingToolView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    // Minimum size to prevent constraint issues on macOS Sequoia
    private static let minSize: CGFloat = 50

    private var frame: CGRect? {
        overlayStateModel.elementInfo?.frame
    }

    private var hasValidFrame: Bool {
        guard let frame = frame else { return false }
        return frame.width > 0 && frame.height > 0
    }

    var body: some View {
        ZStack {
            if hasValidFrame {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white, lineWidth: 1)
                    )
            } else {
                // Transparent placeholder to maintain valid size
                Color.clear
            }
        }
        .frame(
            width: max(frame?.width ?? FloatingToolView.minSize, FloatingToolView.minSize),
            height: max(frame?.height ?? FloatingToolView.minSize, FloatingToolView.minSize)
        )
    }
}
