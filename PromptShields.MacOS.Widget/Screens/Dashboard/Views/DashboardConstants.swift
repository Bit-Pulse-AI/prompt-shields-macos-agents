import SwiftUI

enum DashboardContentState {
    case controlPanel
    case suggestions
    case settings
    case account
}

enum PopupDeleteType: Identifiable {
    var id: String {
        switch self {
        case .channel:
            return "channel"
        case .project:
            return "project"
        case .photo:
            return "photo"
        }
    }
    case channel
    case project
    case photo
    
    var title: String {
        switch self {
        case .channel:
            "Delete channel"
        case .project:
            "Delete project"
        case .photo:
            "Delete photo"
        }
    }
    
    func message(name: String) -> String {
        switch self {
        case .channel:
            "This action cannot be undone. Once deleted, all messages and data in this chat will be permanently removed."
        case .project:
            "This action cannot be undone. Once deleted all channels, messages and data in project \(name) will be permanently removed."
        case .photo:
            "Are you sure you want to delete this photo?"
        }
    }
}

enum PopupType: Identifiable {
    var id: String {
        switch self {
        case .confirmation:
            return "confirmation"
        case .createProject:
            return "createProject"
        case .delete:
            return "delete"
        case .googleKey:
            return "googleKey"
        }
    }
    case confirmation(String, String, () -> Void)
    case createProject((String) -> Void)
    case delete(String, () -> Void, () -> Void)
    case googleKey((String) -> Void)
}

enum DashboardViewParameters {
    private static let collapsedWidth: CGFloat = 64
    private static let expandedWidth: CGFloat = 240
    
    static func sidebarWidth(isCollapsed: Bool) -> CGFloat {
        isCollapsed ? DashboardViewParameters.collapsedWidth : DashboardViewParameters.expandedWidth
    }
} 
