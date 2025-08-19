import SwiftUI

struct FloatingToolView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    private var frame: CGRect? {
        overlayStateModel.elementInfo?.frame
    }
    var body: some View {
        ZStack {
        }
        .frame(width: frame?.width ?? 0, height: frame?.height ?? 0)
        .background(Color.black.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.white, lineWidth: 1)
                )
    }
}
