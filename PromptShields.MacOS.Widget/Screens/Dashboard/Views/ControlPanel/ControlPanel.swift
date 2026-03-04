import SwiftUI

// MARK: - Control Panel View

struct ControlPanelView: View {
    @StateObject private var suggestionsQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
        mapping: DefaultMapping<Suggestion>.self
    )

    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @EnvironmentObject private var overlayState: OverlayStateModel
    @EnvironmentObject private var dashboardState: DashboardStateModel

    private var currentSuggestions: [Suggestion] {
        return suggestionsQueryable.wrappedValue
    }

    private var hasCurrentApplication: Bool {
        return dashboardState.currentApplication != .empty
    }

    private var applicationStatusIndicator: String {
        dashboardState.currentApplication.name
    }

    private var suggestionStatusIndicator: Int {
        currentSuggestions.count
    }

    private var hasSuggestions: Bool {
        currentSuggestions.count > 0
    }

    private var topSuggestions: [Suggestion] {
        Array(currentSuggestions.prefix(5))
    }

    private var monitoringStatusText: String {
        switch accessibilityManager.monitoringState {
        case .disabled:
            return "Disabled"
        case .enabled:
            return "Active"
        case .paused:
            return "Paused"
        case .awaitingPermissions:
            return "Awaiting Permissions"
        }
    }

    private var monitoringStatusColor: Color {
        switch accessibilityManager.monitoringState {
        case .disabled:
            return .secondary
        case .enabled:
            return .green
        case .paused:
            return .orange
        case .awaitingPermissions:
            return .yellow
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Permission Banner (if needed)
                if accessibilityManager.monitoringState == .awaitingPermissions {
                    permissionBanner
                }

                // Monitoring Control
                monitoringControlSection
            }
            .padding()
        }
    }

    // MARK: - Permission Banner

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Accessibility Permission Required")
                    .font(.headline)
            }

            Text("PromptShields needs accessibility permission to detect text fields and provide suggestions. Please grant permission in System Settings.")
                .font(.body)
                .foregroundColor(.secondary)

            HStack {
                Button("Open System Settings") {
                    openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Check Again") {
                    accessibilityManager.refreshPermissionState()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Monitoring Control Section

    private var monitoringControlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitoring Control")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Text Field Monitoring")
                        .font(.body)
                    Text(monitoringStateDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { accessibilityManager.monitoringState == .enabled },
                    set: { newValue in
                        if newValue {
                            accessibilityManager.enableMonitoring()
                        } else {
                            accessibilityManager.disableMonitoring()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .disabled(accessibilityManager.monitoringState == .awaitingPermissions)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            if !accessibilityManager.hasAccessibilityPermission {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Accessibility permission is required to enable monitoring.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var monitoringStateDescription: String {
        switch accessibilityManager.monitoringState {
        case .disabled:
            return "Monitoring is turned off. Enable to detect text fields."
        case .enabled:
            return "Actively monitoring text fields across applications."
        case .paused:
            return "Monitoring paused (screen locked)."
        case .awaitingPermissions:
            return "Waiting for accessibility permissions to be granted."
            }
        }

    // MARK: - Recent Activity Section

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

    // MARK: - Helpers

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
