import SwiftUI

// MARK: - Suggestion Row

struct ControlPanelView: View {
    @StateObject private var suggestionsQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
        mapping: DefaultMapping<Suggestion>.self
    )
    
    private var currentSuggestions: [Suggestion] {
        return suggestionsQueryable.wrappedValue
    }
    
    var hasCurrentApplication: Bool {
        return dashboardState.currentApplication != .empty
    }
    
    var applicationStatusIndicator: String {
        dashboardState.currentApplication.name
    }
    
    var suggestionStatusIndicator: Int {
        currentSuggestions.count
    }
    
    var hasSuggestions: Bool {
        currentSuggestions.count > 0
    }
    
    var topSuggestions: [Suggestion] {
        Array(currentSuggestions.prefix(5))
    }
    
    @EnvironmentObject private var accessibilityManagerImpl: AccessibilityManagerImpl
    @EnvironmentObject private var overlayState: OverlayStateModel
    @EnvironmentObject private var dashboardState: DashboardStateModel
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Welcome Section
                if UserDefaults.standard.bool(forKey: "shouldHideWelcome") != true {
                    welcomeSection
                }
                
                // Quick Stats
                quickStatsSection
            }
            .padding()
        }
    }
    
    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to PromptShields Assistant")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Your AI-powered writing assistant that helps you write better across all applications.")
                .font(.body)
                .foregroundColor(.secondary)
            
            if !dashboardState.isActive {
                Button("Get Started") {
                    Task {
                        await accessibilityManagerImpl.startTimer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Stats")
                .font(.headline)
            
            HStack(spacing: 16) {
                StatCardView(
                    title: "Suggestions Today",
                    value: "\(currentSuggestions.count)",
                    icon: "textformat.abc.dottedunderline",
                    color: .blue
                )
                
                StatCardView(
                    title: "Active Applications",
                    value: hasCurrentApplication ? "1" : "0",
                    icon: "app.badge",
                    color: .green
                )
                
                StatCardView(
                    title: "Status",
                    value: dashboardState.isActive ? "Active" : "Inactive",
                    icon: dashboardState.isActive ? "checkmark.circle.fill" : "xmark.circle.fill",
                    color: dashboardState.isActive ? .green : .red
                )
            }
        }
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
            
            if !hasSuggestions {
                Text("No recent suggestions")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(topSuggestions, id: \.model.uuid) { _ in
                    }
                }
            }
        }
    }
}
