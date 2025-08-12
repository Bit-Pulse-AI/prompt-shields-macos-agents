import SwiftUI

struct DashboardContentHeaderView: View {
    @EnvironmentObject private var dashboardState: DashboardStateModel
    
    var hasCurrentApplication: Bool {
        dashboardState.currentApplication != .empty
    }
    
    var applicationStatusIndicator: String {
        !hasCurrentApplication ? "None" : dashboardState.currentApplication.name
    }
    
    var suggestionStatusIndicator: Int {
        dashboardState.currentSuggestions.count
    }
    var body: some View {
        VStack(spacing: 12) {
            // App Title and Status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PromptShields Assistant")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(dashboardState.isActive ? "Active" : "Inactive")
                        .font(.caption)
                        .foregroundColor(dashboardState.isActive ? .green : .secondary)
                }
                
                Spacer()
                
                // Toggle Button
                Button {
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: dashboardState.isActive ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        Text(dashboardState.isActive ? "Stop" : "Start")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(dashboardState.isActive ? .red : .green)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            // Status Indicators
            if dashboardState.isActive {
                HStack(spacing: 16) {
                    StatusIndicator(
                        title: "Application",
                        value: applicationStatusIndicator,
                        icon: "app.badge"
                    )
                    
                    StatusIndicator(
                        title: "Suggestions",
                        value: "\(suggestionStatusIndicator)",
                        icon: "textformat.abc.dottedunderline"
                    )
                    
                    if dashboardState.isAnalyzing {
                        StatusIndicator(
                            title: "Analyzing",
                            value: "In Progress",
                            icon: "clock"
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
}
