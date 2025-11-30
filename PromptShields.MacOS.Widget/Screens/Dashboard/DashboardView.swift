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
    @Published var isActive: Bool = false
    @Published var isSideMenuCollapsed: Bool = false
    @Published var isSearchVisible: Bool = false
    @Published var contentState: DashboardContentState = .controlPanel
    @Published var currentApplication: ApplicationInfo = .empty
}

struct DashboardView: View {
    @Environment(\.suggestionDomainService) private var suggestionDomainService
    @EnvironmentObject private var dashboardStateModel: DashboardStateModel
    @State private var localValue: CGRect = .zero

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ActionView.self)
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
    }

    private func loadData() async {
        do {
            try await suggestionDomainService.fetchSuggestionTypes()
        } catch {
            logger.error("Error fetching suggestion types \(error)")
        }
    }
}
