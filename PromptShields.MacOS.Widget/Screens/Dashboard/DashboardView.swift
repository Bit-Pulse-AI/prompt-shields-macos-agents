import SwiftUI
import SwiftData
import Combine
import os

struct OverlayInfo {
    let frame: CGRect

    static let empty: OverlayInfo = OverlayInfo(frame: .zero)
}

final class DashboardStateModel: ObservableObject {
    @Published var currentSuggestions: [Suggestion] = []
    @Published var isAnalyzing: Bool = false
    @Published var isSideMenuCollapsed: Bool = false
    @Published var isSearchVisible: Bool = false
    @Published var contentState: DashboardContentState = .controlPanel
    @Published var currentApplication: ApplicationInfo = .empty

    /// Computed property that reflects the accessibility manager's state
    /// This is kept for backward compatibility with views that use isActive
    var isActive: Bool {
        // This will be updated via Combine subscription from AccessibilityManager
        _isActive
    }

    @Published private var _isActive: Bool = false

    func updateIsActive(_ value: Bool) {
        _isActive = value
    }
}

struct DashboardView: View {
    @Environment(\.suggestionDomainService) private var suggestionDomainService
    @EnvironmentObject private var dashboardStateModel: DashboardStateModel
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @State private var localValue: CGRect = .zero

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: DashboardView.self)
    )

    var body: some View {
        HStack(spacing: .zero) {
            DashboardSidebarView()
            DashboardContentAreaView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(dashboardStateModel)
        .dashboardStyle()
        .task {
            await loadData()
        }
        .onReceive(accessibilityManager.$monitoringState) { state in
            dashboardStateModel.updateIsActive(state == .enabled)
        }
        .onReceive(accessibilityManager.$applicationInfo) { info in
            dashboardStateModel.currentApplication = info
        }
    }

    private func loadData() async {
        do {
            try await suggestionDomainService.fetchSuggestionTypes()
        } catch {
            logger.debug("Error fetching suggestion types \(error)")
        }
    }
}
