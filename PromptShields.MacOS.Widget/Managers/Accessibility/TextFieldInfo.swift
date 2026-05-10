import AppKit

// MARK: - Element Info

/// Information about a focused UI element for accessibility operations
/// Conforms to Sendable for safe concurrent access in Swift 6
///
/// Note: This struct stores metadata about the element. The actual AXUIElement
/// is acquired fresh at injection time via TextInjectionService for reliability.
struct ElementInfo: Equatable, Hashable, Sendable {
    // MARK: - Properties

    /// The text content of the element
    var text: String

    /// The name of the application containing the element
    let applicationName: String

    /// The bundle identifier of the application
    let applicationBundleId: String

    /// The frame of the element in screen coordinates
    var frame: CGRect

    /// Identifier for the element (used for tracking, not for element lookup)
    let elementIdentifier: AXElementID?

    /// Whether the text came from a user selection
    let isSelectedText: Bool

    /// URL of the document hosting the focused element, when available.
    /// Populated by FocusTracker for browser apps from AXURL on the
    /// nearest AXWebArea ancestor. Nil for native-app text fields.
    /// Used by AI-SPM to populate `PolicyViolation.evidence.urlHost`.
    let focusedURL: String?

    // MARK: - Initialization

    init(
        text: String,
        applicationName: String,
        applicationBundleId: String,
        frame: CGRect,
        elementIdentifier: AXElementID?,
        isSelectedText: Bool = false,
        focusedURL: String? = nil
    ) {
        self.text = text
        self.applicationName = applicationName
        self.applicationBundleId = applicationBundleId
        self.frame = frame
        self.elementIdentifier = elementIdentifier
        self.isSelectedText = isSelectedText
        self.focusedURL = focusedURL
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(applicationName)
        hasher.combine(applicationBundleId)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(frame.size.width)
        hasher.combine(frame.size.height)
        hasher.combine(isSelectedText)
        hasher.combine(elementIdentifier)
        hasher.combine(focusedURL)
    }

    // MARK: - Equatable

    static func == (lhs: ElementInfo, rhs: ElementInfo) -> Bool {
            lhs.applicationBundleId == rhs.applicationBundleId &&
            lhs.applicationName == rhs.applicationName &&
            lhs.text == rhs.text &&
            lhs.frame == rhs.frame &&
        lhs.elementIdentifier == rhs.elementIdentifier &&
            lhs.isSelectedText == rhs.isSelectedText &&
            lhs.focusedURL == rhs.focusedURL
    }

    // MARK: - URL helpers

    /// Host portion of `focusedURL` (e.g. `chat.openai.com`).
    /// Used for both Promptly's MonitoredApps.webHosts matching and the
    /// AI-SPM violation envelope's `evidence.urlHost`.
    var focusedURLHost: String? {
        guard let raw = focusedURL, !raw.isEmpty else { return nil }
        if let url = URL(string: raw), let host = url.host, !host.isEmpty {
            return host.lowercased()
        }
        return nil
    }

    // MARK: - Validation

    /// Checks if the element identifier matches the current one in the registry
    @MainActor
    var isCurrentElement: Bool {
        guard let id = elementIdentifier else { return false }
        return AXElementRegistry.shared.isValid(id)
    }
}

// MARK: - Application Info

/// Information about the current foreground application
struct ApplicationInfo: Equatable, Sendable {
    // MARK: - Properties

    /// The localized name of the application
    let name: String

    /// The bundle identifier of the application
    let bundleId: String?

    // MARK: - Static Properties

    /// Empty application info
    static let empty = ApplicationInfo(name: "", bundleId: nil)

    // MARK: - Initialization

    init(name: String, bundleId: String? = nil) {
        self.name = name
        self.bundleId = bundleId
    }
}
