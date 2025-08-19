import SwiftUI
import SwiftData
import Combine

struct ApplicationInfo: Equatable {
    let name: String
    
    static let empty: ApplicationInfo = .init(name: "")
}

struct OverlayInfo {
    let frame: CGRect
    
    static let empty: OverlayInfo = OverlayInfo(frame: .zero)
}

final class DashboardStateModel: ObservableObject {
    @Published var currentSuggestions: [Suggestion] = []
    @Published var isAnalyzing: Bool = false
    @Published var isActive: Bool = false
    @Published var isSideMenuCollapsed: Bool = false
    @Published var isSearchVisible: Bool = false
    @Published var contentState: DashboardContentState = .controlPanel
    @Published var currentApplication: ApplicationInfo = .empty
}

struct DashboardView: View {
    @EnvironmentObject private var dashboardStateModel: DashboardStateModel
    @State private var localValue: CGRect = .zero

    var body: some View {
        HStack(spacing: .zero) {
            DashboardSidebarView()
            DashboardContentAreaView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(dashboardStateModel)
        .dashboardStyle()
    }
}
