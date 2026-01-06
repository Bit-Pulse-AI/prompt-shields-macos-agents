import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    private var hasElementInfo: Bool {
        overlayStateModel.elementInfo != nil
    }

    var body: some View {
        if hasElementInfo {
            FloatingToolView()
        } else {
            // Minimal placeholder - window will be hidden anyway
            Color.clear
                .frame(width: 50, height: 50)
        }
    }
}
