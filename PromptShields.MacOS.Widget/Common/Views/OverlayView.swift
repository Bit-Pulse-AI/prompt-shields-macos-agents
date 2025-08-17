import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    
    var body: some View {
        ZStack(alignment: .leading) {
            FloatingToolView()
                .frame(width: overlayStateModel.elementInfo?.frame.width ?? 0, height: overlayStateModel.elementInfo?.frame.height ?? 0)
                .background(Color.clear)
        }
        .frame(alignment: .top)
    }
}

struct TestView: View {
    var body: some View {
        OverlayView()
    }
}
