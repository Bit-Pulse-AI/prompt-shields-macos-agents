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
                // Minimal placeholder with valid size to prevent constraint issues on Sequoia
                Color.clear
                    .frame(minWidth: 50, minHeight: 50)
            }
        }
        .frame(minWidth: 50, minHeight: 50, alignment: .top)
    }
}
