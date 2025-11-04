import AppKit

// MARK: - Text Field Information
struct ElementInfo: Equatable, Hashable {
    var text: String
    let applicationName: String
    let applicationBundleId: String
    var frame: CGRect
    let element: AXUIElement?
    let isSelectedText: Bool // Track if text came from user selection

    init(text: String, applicationName: String, applicationBundleId: String, frame: CGRect, element: AXUIElement?, isSelectedText: Bool = false) {
        self.text = text
        self.applicationName = applicationName
        self.applicationBundleId = applicationBundleId
        self.frame = frame
        self.element = element
        self.isSelectedText = isSelectedText
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(applicationName)
        hasher.combine(applicationBundleId)
        hasher.combine(frame)
        hasher.combine(isSelectedText)
    }

    static func == (lhs: ElementInfo, rhs: ElementInfo) -> Bool {
        return
            lhs.applicationBundleId == rhs.applicationBundleId &&
            lhs.applicationName == rhs.applicationName &&
            lhs.text == rhs.text &&
            lhs.frame == rhs.frame &&
            lhs.element == rhs.element &&
            lhs.isSelectedText == rhs.isSelectedText
    }
}
