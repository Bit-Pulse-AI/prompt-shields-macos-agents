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
                MonitoredAppsSection()
                SuggestionTypeListView()
                    .frame(minHeight: 400)
            }
            .padding(PSSpacing.panel)
        }
        .background(Color.psBg)
    }
}

// MARK: - Monitored Apps Section (PS-13)

private struct MonitoredAppsSection: View {
    @State private var refreshToken = UUID()

    private var apps: [MonitoredApp] {
        MonitoredAppsRegistry.shared.apps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PSSpacing.md) {
            HStack {
                Text("MONITORED APPS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.psText3)
                Spacer()
                Text("\(apps.filter { MonitoredAppsRegistry.shared.isEnabled($0) }.count) of \(apps.count) enabled")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.psText3)
            }
            .padding(.horizontal, PSSpacing.xs)

            VStack(spacing: 0) {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    MonitoredAppRow(
                        app: app,
                        isEnabled: MonitoredAppsRegistry.shared.isEnabled(app),
                        onToggle: { newValue in
                            MonitoredAppsRegistry.shared.setEnabled(app, enabled: newValue)
                            refreshToken = UUID()
                        },
                        showsDivider: index < apps.count - 1
                    )
                    .id(refreshToken.hashValue ^ app.id.hashValue)
                }
            }
            .background(Color.psSurface)
            .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                    .stroke(Color.psBorder, lineWidth: 1)
            )

            Text("Promptly only reads text fields in the apps you enable here. Changes apply immediately.")
                .font(.system(size: 12))
                .foregroundStyle(Color.psText3)
                .padding(.horizontal, PSSpacing.xs)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MonitoredAppRow: View {
    let app: MonitoredApp
    let isEnabled: Bool
    let onToggle: (Bool) -> Void
    let showsDivider: Bool

    @State private var toggleState: Bool

    init(app: MonitoredApp, isEnabled: Bool, onToggle: @escaping (Bool) -> Void, showsDivider: Bool) {
        self.app = app
        self.isEnabled = isEnabled
        self.onToggle = onToggle
        self.showsDivider = showsDivider
        self._toggleState = State(initialValue: isEnabled)
    }

    private var categoryBadge: String {
        switch app.category {
        case .native: return "Native app"
        case .web: return "Web"
        case .mixed: return "Native & Web"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: PSSpacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.psText)
                    HStack(spacing: 6) {
                        Text(categoryBadge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.psText3)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.psBg2)
                            .clipShape(Capsule())
                        if let host = app.webHosts.first {
                            Text(host)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.psText3)
                        }
                    }
                }
                Spacer(minLength: PSSpacing.md)
                Toggle("", isOn: Binding(
                    get: { toggleState },
                    set: { newValue in
                        toggleState = newValue
                        onToggle(newValue)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.horizontal, PSSpacing.lg)
            .padding(.vertical, 12)

            if showsDivider {
                Divider().background(Color.psBg3)
            }
        }
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
