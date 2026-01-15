import SwiftUI
import AppKit

/// A window that displays information about the application
class AboutWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        self.title = "About PromptShields"
        self.center()
        self.isReleasedWhenClosed = true
        self.level = .floating
        self.delegate = self

        // Create the content view
        let contentView = AboutView(window: self)
        let hostingView = NSHostingView(rootView: contentView)
        self.contentView = hostingView
    }
}

// MARK: - NSWindowDelegate
extension AboutWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Switch back to accessory mode when about window is closed
//        NSApp.setActivationPolicy(.accessory)
    }
}

/// SwiftUI view for the about dialog
struct AboutView: View {
    let window: NSWindow

    init(window: NSWindow) {
        self.window = window
    }

    var body: some View {
        VStack(spacing: 20) {
            // App icon and name
            VStack(spacing: 12) {
                Image(ImageResource(name: "logo_about", bundle: .main))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)

                Text("PromptShields")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // App description
            VStack(spacing: 8) {
                Text("AI-powered prompt enhancement and security tool")
                    .font(.body)
                    .multilineTextAlignment(.center)

                Text("Protect your privacy and enhance your AI interactions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Copyright and company info
            VStack(spacing: 4) {
                Text("© 2026 Promptshields")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("All rights reserved")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Close button
            Button("Close") {
                window.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(30)
        .frame(width: 400, height: 400)
    }

    /// Gets the app version from the bundle
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
