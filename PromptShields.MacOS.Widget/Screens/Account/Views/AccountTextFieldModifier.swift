import SwiftUI

struct AccountTextFieldModifier: ViewModifier {
    var foregroundColor: Color
    var backgroundColor: Color
    var borderColor: Color
    var cornerRadius: CGFloat
    var padding: CGFloat = 10 // Default padding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(cornerRadius)
            .textFieldStyle(.plain)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}
