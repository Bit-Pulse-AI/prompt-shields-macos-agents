import SwiftUI

struct ExpandingTextEditor: View {
    @Binding var text: String

    var body: some View {
        ResizableTextView(text: $text,
                          placeholderTextColor: Color.onSurfaceVariant.nsColor,
                          placeholderText: "Enter text or a prompt to check")
            .textFieldStyle(.plain)
            .cornerRadius(4)
    }
}
