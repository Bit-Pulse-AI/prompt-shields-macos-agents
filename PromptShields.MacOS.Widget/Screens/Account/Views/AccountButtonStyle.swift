import SwiftUI

struct AccountButtonStyle: ButtonStyle {
    var foregroundColor: Color
    var backgroundColor: Color
    var borderColor: Color
    var cornerRadius: CGFloat
    var imageName: String?

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            if let imageName = imageName {
                Image(ImageResource(name: imageName, bundle: .main))
                    .foregroundColor(foregroundColor)
            }
            configuration.label
                .foregroundColor(foregroundColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .cornerRadius(cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: 1)
        )
        .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
        .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
