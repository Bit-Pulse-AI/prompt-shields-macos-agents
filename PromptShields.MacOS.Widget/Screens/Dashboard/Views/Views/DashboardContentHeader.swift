import SwiftUI

struct DashboardContentHeaderView: View {
    @EnvironmentObject private var overlayState: OverlayStateModel
    @EnvironmentObject private var dashboardState: DashboardStateModel
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    
    @StateObject private var suggestionsQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
        mapping: DefaultMapping<Suggestion>.self
    )
    
    private var currentSuggestions: [Suggestion] {
        return suggestionsQueryable.wrappedValue
    }
    
    var hasCurrentApplication: Bool {
        overlayState.elementInfo?.applicationBundleId != nil
    }
    
    var applicationStatusIndicator: String {
        overlayState.elementInfo?.applicationName ?? "None"
    }
    
    var suggestionStatusIndicator: Int {
        currentSuggestions.count
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
                    if dashboardState.isActive {
                        Task {
                            await accessibilityManager.stopTimer()
                        }
                    } else {
                        Task {
                            overlayState.elementInfo = nil
                            overlayState.actionToolState = .idle
                            await accessibilityManager.startTimer()
                        }
                    }
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
//            if dashboardState.isActive {
//                HStack(spacing: 16) {
//                    StatusIndicator(
//                        title: "Application",
//                        value: applicationStatusIndicator,
//                        icon: "app.badge"
//                    )
//                    
//                    StatusIndicator(
//                        title: "Suggestions",
//                        value: "\(suggestionStatusIndicator)",
//                        icon: "textformat.abc.dottedunderline"
//                    )
//                    
//                    if dashboardState.isAnalyzing {
//                        StatusIndicator(
//                            title: "Analyzing",
//                            value: "In Progress",
//                            icon: "clock"
//                        )
//                    }
//                }
//            }
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
