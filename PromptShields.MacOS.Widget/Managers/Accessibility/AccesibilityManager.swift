import SwiftUI

protocol AccessibilityManager: ObservableObject {
}

extension EnvironmentValues {
    var accessibilityManager: AccessibilityManagerImpl {
        get { self[AccessibilityManagerKey.self] }
        set { self[AccessibilityManagerKey.self] = newValue }
    }
}

struct AccessibilityManagerKey: EnvironmentKey {
    static let defaultValue = {
        return AccessibilityManagerImpl()
    }()
}

actor AccessibilityManagerImpl: AccessibilityManager {
}
