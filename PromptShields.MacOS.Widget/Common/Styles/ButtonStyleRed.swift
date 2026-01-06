import SwiftUI

struct ButtonStyleRed: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .font(NSFont.body3.swiftUIFont)
                .foregroundStyle(.white)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.red)
        .cornerRadius(8)
        .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
        .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
