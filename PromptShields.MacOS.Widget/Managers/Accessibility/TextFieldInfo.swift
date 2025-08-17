import AppKit

// MARK: - Text Field Information
struct ElementInfo: Equatable, Hashable {
    let text: String
    let applicationName: String
    let applicationBundleId: String
    var frame: CGRect
    
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
            lhs.frame == rhs.frame
    }
}
