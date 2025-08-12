import AppKit

class PlaceholderTextView: NSTextView, Sendable {
    var action: (() -> Void)?
    
    var placeholder: String = "Enter your text here..." {
        didSet {
            self.needsDisplay = true // Redraw when placeholder changes
        }
    }
    
    // Placeholder text color
    var placeholderTextColor: NSColor = .placeholderTextColor {
        didSet {
            self.needsDisplay = true // Redraw when color changes
        }
    }
    
    override func paste(_ sender: Any?) {
       guard let pasteboardString = NSPasteboard.general.string(forType: .string) else {
           return 
       }
       self.insertText(pasteboardString, replacementRange: self.selectedRange())
   }
    
    override func keyDown(with event: NSEvent) {
        // Check for the Command key and Enter key
        if event.keyCode == 36 { // 36 is the keycode for Enter
            if event.modifierFlags.contains(.command) {
                // Command + Enter: Insert a new line
                self.insertNewlineIgnoringFieldEditor(self)
            } else {
                // Enter: Trigger an action
                triggerAction()
            }
        } else {
            // For all other keys, handle as usual
            super.keyDown(with: event)
        }
    }
    
    private func triggerAction() {
        self.action?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Check if the text view is empty
        if string.isEmpty {
            // Draw the placeholder text
            let placeholderAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: placeholderTextColor,
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
            placeholder.draw(in: bounds.insetBy(dx: 5, dy: 5), withAttributes: placeholderAttributes)
        }
    }

    override func becomeFirstResponder() -> Bool {
        self.needsDisplay = true // Redraw to remove placeholder when focused
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        self.needsDisplay = true // Redraw to show placeholder when focus is lost
        return super.resignFirstResponder()
    }
}
