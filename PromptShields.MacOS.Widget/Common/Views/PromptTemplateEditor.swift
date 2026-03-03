import SwiftUI
import AppKit

/// A custom text editor for prompt templates that displays the {{TEXT}} placeholder
/// as a movable bubble widget that can be repositioned within the text
struct PromptTemplateEditor: View {
    @Binding var text: String

    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @FocusState private var isFocused: Bool

    private let placeholder = SuggestionType.textPlaceholder

    var body: some View {
        PromptTemplateTextView(
            text: $text,
            selectedRange: $selectedRange,
            placeholder: placeholder
        )
        .font(.system(.body, design: .monospaced))
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - NSViewRepresentable for Custom Text View

struct PromptTemplateTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 4)

        // Configure layout manager for custom drawing
        textView.layoutManager?.delegate = context.coordinator

        // Set initial text with styled placeholder
        updateTextViewContent(textView, with: text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if text has changed externally
        if textView.string != text {
            let currentSelection = textView.selectedRange()
            updateTextViewContent(textView, with: text)

            // Restore selection if possible
            if currentSelection.location + currentSelection.length <= textView.string.count {
                Task {
                    await MainActor.run {
                        textView.setSelectedRange(currentSelection)
                    }
                }
            }
        }
    }

    private func updateTextViewContent(_ textView: NSTextView, with content: String) {
        let attributedString = createAttributedString(from: content)
        Task {
            await MainActor.run {
                textView.textStorage?.setAttributedString(attributedString)
            }
        }
    }

    private func createAttributedString(from content: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]

        // Split the content by the placeholder and reconstruct with styled placeholders
        let parts = content.components(separatedBy: placeholder)

        for (index, part) in parts.enumerated() {
            // Add the normal text part
            attributedString.append(NSAttributedString(string: part, attributes: normalAttributes))

            // Add styled placeholder if not the last part
            if index < parts.count - 1 {
                let placeholderAttributed = createPlaceholderBubble()
                attributedString.append(placeholderAttributed)
            }
        }

        return attributedString
    }

    private func createPlaceholderBubble() -> NSAttributedString {
        // Create a styled placeholder that looks like a bubble
        let placeholderAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.systemBlue.withAlphaComponent(0.85),
            .baselineOffset: 1.0
        ]

        // Use the display text for the bubble
        let displayText = " 📝 Your Text "
        return NSAttributedString(string: displayText, attributes: placeholderAttributes)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: PromptTemplateTextView
        private var isUpdating = false

        init(_ parent: PromptTemplateTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }

            isUpdating = true
            defer { isUpdating = false }

            // Get the raw text content
            let rawText = textView.string

            // Convert display placeholder back to the actual placeholder
            let displayPlaceholder = " 📝 Your Text "
            let actualText = rawText.replacingOccurrences(of: displayPlaceholder, with: parent.placeholder)

            // Update the binding
            parent.text = actualText

            // Re-apply styling
            let currentSelection = textView.selectedRange()
            parent.updateTextViewContent(textView, with: actualText)

            // Adjust selection if needed
            let newLength = textView.string.count
            if currentSelection.location <= newLength {
                let adjustedLength = min(currentSelection.length, newLength - currentSelection.location)
                textView.setSelectedRange(NSRange(location: min(currentSelection.location, newLength), length: adjustedLength))
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        PromptTemplateEditor(text: .constant("Simplify the following text:\n\n{{TEXT}}\n\nMake it easier to understand."))
            .frame(height: 200)
            .padding()
    }
    .frame(width: 400, height: 300)
}
