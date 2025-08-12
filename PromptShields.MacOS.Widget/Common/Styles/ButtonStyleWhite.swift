import SwiftUI

struct ButtonStyleWhite: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .font(NSFont.body3.swiftUIFont)
                .foregroundColor(.black)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.border, lineWidth: 1)
        )
        .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
        .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
