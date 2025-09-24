import SwiftUI

struct OverlayView: View {
    var body: some View {
        ZStack(alignment: .leading) {
            FloatingToolView()
                .background(Color.clear)
        }
        .frame(alignment: .top)
    }
}
