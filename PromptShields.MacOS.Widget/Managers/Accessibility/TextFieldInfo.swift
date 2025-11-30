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

    // MARK: - Initialization

    init(
        text: String,
        applicationName: String,
        applicationBundleId: String,
        frame: CGRect,
        elementIdentifier: AXElementID?,
        isSelectedText: Bool = false
    ) {
        self.text = text
        self.applicationName = applicationName
        self.applicationBundleId = applicationBundleId
        self.frame = frame
        self.elementIdentifier = elementIdentifier
        self.isSelectedText = isSelectedText
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
    }

    // MARK: - Equatable

    static func == (lhs: ElementInfo, rhs: ElementInfo) -> Bool {
        lhs.applicationBundleId == rhs.applicationBundleId &&
        lhs.applicationName == rhs.applicationName &&
        lhs.text == rhs.text &&
        lhs.frame == rhs.frame &&
        lhs.elementIdentifier == rhs.elementIdentifier &&
        lhs.isSelectedText == rhs.isSelectedText
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
