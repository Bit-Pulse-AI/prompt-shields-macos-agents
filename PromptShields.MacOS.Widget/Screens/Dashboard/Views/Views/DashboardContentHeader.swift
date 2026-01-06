import SwiftUI

@MainActor
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
                            accessibilityManager.stopTimer()
                        }
                    } else {
                        Task {
                            await MainActor.run {
                                overlayState.elementInfo = nil
                                overlayState.actionToolState = .idle
                            }
                            accessibilityManager.startTimer()
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
