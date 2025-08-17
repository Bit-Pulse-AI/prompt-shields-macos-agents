import SwiftUI

struct ResizableTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var dynamicHeight: CGFloat
    let placeholderTextColor: NSColor
    let placeholderText: String
    
    func makeNSView(context: Context) -> NSTextView {
        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.placeholder = placeholderText
        textView.placeholderTextColor = placeholderTextColor
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.textContainerInset = CGSize(width: 5, height: 5)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = .body1
        textView.textColor = .black
        return textView
    }

    @MainActor
    func updateNSView(_ nsView: NSTextView, context: Context) {
        if nsView.string != text {
            nsView.string = text
        }
        dynamicHeight = calculateHeight(for: nsView)
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    private func calculateHeight(for textView: NSTextView) -> CGFloat {
        let layoutManager = textView.layoutManager!
        let textContainer = textView.textContainer!
        let size = layoutManager.usedRect(for: textContainer).size
        let inset = textView.textContainerInset
        return max(40, size.height + inset.height * 2)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ResizableTextView

        init(_ parent: ResizableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                parent.text = textView.string
            }
        }
    }
}
