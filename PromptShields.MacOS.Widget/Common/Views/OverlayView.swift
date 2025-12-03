import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    private var hasElementInfo: Bool {
        overlayStateModel.elementInfo != nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if hasElementInfo {
                FloatingToolView()
                    .background(Color.clear)
            } else {
                // Minimal placeholder to keep window alive
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
        .frame(alignment: .top)
    }
}
