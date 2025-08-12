import AppKit

// MARK: - Text Field Information
struct TextFieldInfo: Equatable, Hashable {
    let element: AXUIElement
    let applicationName: String
    let applicationBundleId: String
    let elementType: String
    let elementRole: String
    let frame: CGRect
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(applicationBundleId)
        hasher.combine(elementType)
        hasher.combine(elementRole)
        hasher.combine(frame)
    }
    
    static func == (lhs: TextFieldInfo, rhs: TextFieldInfo) -> Bool {
        return lhs.applicationBundleId == rhs.applicationBundleId &&
               lhs.elementType == rhs.elementType &&
               lhs.elementRole == rhs.elementRole &&
               lhs.frame == rhs.frame
    }
}
