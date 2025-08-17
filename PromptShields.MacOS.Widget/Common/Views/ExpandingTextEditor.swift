import SwiftUI

struct ExpandingTextEditor: View {
    @Binding var text: String
    @Binding var height: CGFloat
    
    var body: some View {
        ResizableTextView(text: $text,
                          dynamicHeight: $height,
                          placeholderTextColor: Color.onSurfaceVariant.nsColor,
                          placeholderText: "Enter text or a prompt to check")
            .frame(height: height)
            .textFieldStyle(.plain)
            .cornerRadius(4)
    }
}
