import SwiftUI

struct ChevronButton: View {
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(spacing: .zero) {
            Button {
                withAnimation {
                    self.isCollapsed = false
                }
            } label: {
                ZStack(alignment: .center) {
                    Circle()
                        .stroke(style: .init(lineWidth: 1))
                        .foregroundStyle(Color.border)
                        .background(Color.onPrimary)
                    Image(ImageResource(name: "double_chevron", bundle: .main))
                        .renderingMode(.template)
                        .foregroundStyle(Color.doubleChevron)
                }
                .clipShape(Circle())
                .frame(width: 32,
                       height: 32,
                       alignment: .center)
            }
            .padding(.leading, -16)
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(alignment: .top)
    }
}
