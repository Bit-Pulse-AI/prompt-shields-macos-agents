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
    @StateObject private var dashboardStateModel = DashboardStateModel()
    @StateObject private var accessibilityMonitorService: AccessibilityMonitorService
    @State private var localValue: CGRect = .zero
    private var overlayStateModel: StateObject<OverlayStateModel>
    private var cancellables = Set<AnyCancellable>()
    
    init(overlayStateModel: StateObject<OverlayStateModel>) {
        self.overlayStateModel = overlayStateModel
        self._accessibilityMonitorService = StateObject(wrappedValue: AccessibilityMonitorService(overlayStateModel: overlayStateModel))
    }

    var body: some View {
        HStack(spacing: .zero) {
            DashboardSidebarView()
            DashboardContentAreaView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(dashboardStateModel)
        .environmentObject(accessibilityMonitorService)
        .dashboardStyle()
    }
}
