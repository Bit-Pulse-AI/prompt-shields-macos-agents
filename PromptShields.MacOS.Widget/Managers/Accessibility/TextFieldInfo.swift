import AppKit

// MARK: - Text Field Information
struct ElementInfo: Equatable, Hashable {
    var text: String
    let applicationName: String
    let applicationBundleId: String
    var frame: CGRect
    let element: AXUIElement?
        
    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
        hasher.combine(applicationName)
        hasher.combine(applicationBundleId)
        hasher.combine(frame)
    }
    
    static func == (lhs: ElementInfo, rhs: ElementInfo) -> Bool {
        return
            lhs.applicationBundleId == rhs.applicationBundleId &&
            lhs.applicationName == rhs.applicationName &&
            lhs.text == rhs.text &&
            lhs.frame == rhs.frame &&
            lhs.element == rhs.element
    }
}
