import SwiftUI

struct RoundBox<Content: View>: View {
    var body: some View {
        VStack(spacing: .zero) {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(NSFont.heading3.swiftUIFont)
                    .foregroundStyle(Color.onSurface)
                makeContent()
            }
            .padding(32)
            .background(.white)
            .roundedCorners(radius: 12, corners: .allCorners)
        }
        .padding(.horizontal, 24)
    }
    private let title: String
    private let makeContent: () -> Content

    init(title: String, makeContent: @escaping () -> Content) {
        self.makeContent = makeContent
        self.title = title
    }
}
