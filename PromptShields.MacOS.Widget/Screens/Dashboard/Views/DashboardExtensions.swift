import SwiftUI

// MARK: - Dashboard View Extensions

extension View {
    /// Applies common dashboard styling
    func dashboardStyle() -> some View {
        self
            .background(Color.background)
            .toolbarVisibility(.hidden, for: .automatic)
    }
}
