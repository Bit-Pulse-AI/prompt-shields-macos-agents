import SwiftUI

// MARK: - Suggestion Row

struct ControlPanelView: View {
    var hasCurrentApplication: Bool {
        dashboardState.currentApplication != .empty
    }
    
    var applicationStatusIndicator: String {
        !hasCurrentApplication ? "None" : dashboardState.currentApplication.name
    }
    
    var suggestionStatusIndicator: Int {
        dashboardState.currentSuggestions.count
    }
    
    var hasSuggestions: Bool {
        dashboardState.currentSuggestions.count > 0
    }
    
    var topSuggestions: [Suggestion] {
        Array(dashboardState.currentSuggestions.prefix(5))
    }
    
    @EnvironmentObject private var dashboardState: DashboardStateModel
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Welcome Section
                welcomeSection
                
                // Quick Stats
                quickStatsSection
                
                // Recent Activity
                recentActivitySection
                
                // Quick Actions
                quickActionsSection
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
//                    coordinator.start()
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
                    value: "\(dashboardState.currentSuggestions.count)",
                    icon: "textformat.abc.dottedunderline",
                    color: .blue
                )
                
                StatCardView(
                    title: "Active Applications",
                    value: hasCurrentApplication ? "0" : "1",
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
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            HStack(spacing: 12) {
                Button("Start Assistant") {
//                    coordinator.start()
                }
                .buttonStyle(.bordered)
                .disabled(dashboardState.isActive)
                
                Button("Stop Assistant") {
//                    coordinator.stop()
                }
                .buttonStyle(.bordered)
                .disabled(!dashboardState.isActive)
                
                Button("Settings") {
                    // Navigate to settings tab
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
