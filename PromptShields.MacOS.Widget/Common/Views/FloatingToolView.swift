import SwiftUI

struct FloatingToolView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    private var frame: CGRect? {
        overlayStateModel.elementInfo?.frame
    }

    private var hasValidFrame: Bool {
        guard let frame = frame else { return false }
        return frame.width > 0 && frame.height > 0
    }

    var body: some View {
        if hasValidFrame, let frame = frame {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white, lineWidth: 1)
                )
                .frame(width: frame.width, height: frame.height)
        } else {
            Color.clear
                .frame(width: 50, height: 50)
        }
    }
}
