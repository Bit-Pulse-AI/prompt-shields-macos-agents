import SwiftUI

struct NavigationTitleModifier: ViewModifier {
    let navigationTitle: String?
    
    func body(content: Content) -> some View {
        if let navigationTitle {
            content.navigationTitle(navigationTitle)
        } else {
            content
        }
    }
}
