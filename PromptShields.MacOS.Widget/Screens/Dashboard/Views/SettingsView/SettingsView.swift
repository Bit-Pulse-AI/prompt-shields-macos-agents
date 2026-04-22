import SwiftUI
import os

/// Settings view: Monitoring + Suggestion Types.
/// Text Field Monitoring toggle lives here per PS-09.
struct SettingsView: View {
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SettingsView.self)
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PSSpacing.xl) {
                MonitoringSection(accessibilityManager: accessibilityManager)
                SuggestionTypeListView()
                    .frame(minHeight: 400)
            }
            .padding(PSSpacing.panel)
        }
        .background(Color.psBg)
    }
}

// MARK: - Monitoring Section (PS-09)

private struct MonitoringSection: View {
    @ObservedObject var accessibilityManager: AccessibilityManagerImpl

    private var isActive: Bool {
        accessibilityManager.monitoringState == .enabled
    }

    private var awaitingPermission: Bool {
        accessibilityManager.monitoringState == .awaitingPermissions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PSSpacing.md) {
            Text("MONITORING")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.psText3)
                .padding(.horizontal, PSSpacing.xs)

            VStack(spacing: 0) {
                row(
                    title: "Text Field Monitoring",
                    subtitle: subtitle,
                    toggleBinding: Binding(
                        get: { isActive },
                        set: { newValue in
                            if newValue {
                                accessibilityManager.enableMonitoring()
                            } else {
                                accessibilityManager.disableMonitoring()
                            }
                        }
                    )
                )
            }
            .background(Color.psSurface)
            .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                    .stroke(Color.psBorder, lineWidth: 1)
            )
        }
    }

    private var subtitle: String {
        switch accessibilityManager.monitoringState {
        case .disabled:
            return "Monitoring is off. Turn on to detect text fields across apps."
        case .enabled:
            return "Actively monitoring text fields across your AI tools."
        case .paused:
            return "Paused (screen locked). Resumes automatically."
        case .awaitingPermissions:
            return "Waiting for accessibility permission. Grant it in the Control Panel."
        }
    }

    private func row(title: String, subtitle: String, toggleBinding: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: PSSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.psText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.psText3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: PSSpacing.md)
            Toggle("", isOn: toggleBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(awaitingPermission)
        }
        .padding(.horizontal, PSSpacing.lg)
        .padding(.vertical, 14)
    }
}
