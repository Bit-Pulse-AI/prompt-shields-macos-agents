import SwiftUI

struct ExpandingTextEditor: View {
    @Binding var text: String
    @State private var height: CGFloat = 40
    let action: () -> Void
    
    var body: some View {
        ResizableTextView(text: $text,
                          dynamicHeight: $height,
                          placeholderTextColor: Color.onSurfaceVariant.nsColor,
                          placeholderText: "Enter text or a prompt to check") {
            self.action()
        }
            .frame(height: height)
            .textFieldStyle(.plain)
            .cornerRadius(4)
    }
}
