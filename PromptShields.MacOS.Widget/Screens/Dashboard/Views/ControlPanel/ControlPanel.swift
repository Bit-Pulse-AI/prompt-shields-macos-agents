import SwiftUI

// Control Panel (redesigned per PRD PS-07/08/09 + Feb 2025 HTML mockup).
//
// Structure: (1) status card with "Turn on Promptly" button,
//            (2) quick stats row, (3) suggestion-types overview.
// The monitoring toggle + permission ask live on the button itself — a
// separate "Text Field Monitoring" toggle lives in Settings (PS-09).

struct ControlPanelView: View {
    @StateObject private var suggestionsQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
        mapping: DefaultMapping<Suggestion>.self
    )
    @StateObject private var typesQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.sortOrder, order: .forward)],
        mapping: DefaultMapping<SuggestionType>.self
    )

    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @EnvironmentObject private var dashboardState: DashboardStateModel

    @State private var shieldActivePulse: Bool = false

    private var isShieldActive: Bool {
        accessibilityManager.monitoringState == .enabled
    }

    private var awaitingPermission: Bool {
        accessibilityManager.monitoringState == .awaitingPermissions
            || !accessibilityManager.hasAccessibilityPermission
    }

    private var suggestions: [Suggestion] {
        suggestionsQueryable.wrappedValue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PSSpacing.xl) {
                if awaitingPermission {
                    PermissionBanner {
                        openAccessibilitySettings()
                    }
                }

                ShieldStatusCard(
                    isActive: isShieldActive,
                    awaitingPermission: awaitingPermission,
                    pulse: shieldActivePulse,
                    onPrimaryAction: handlePrimaryAction
                )

                QuickStatsRow(stats: computeStats())
                    .tourAnchor("control-panel-quick-stats")

                SuggestionOverviewSection(
                    types: typesQueryable.wrappedValue,
                    onOpenSettings: { dashboardState.contentState = .settings }
                )
                .tourAnchor("control-panel-suggestion-overview")
            }
            .padding(PSSpacing.panel)
        }
        .background(Color.psBg)
        .onAppear {
            shieldActivePulse = true
            // Q2: 1.2s breather after the dashboard mounts before the
            // intro tour kicks in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                TourCoordinator.shared.autoStart(trigger: .firstDashboardMount)
            }
        }
    }

    private func handlePrimaryAction() {
        if awaitingPermission {
            openAccessibilitySettings()
            return
        }
        if isShieldActive {
            accessibilityManager.disableMonitoring()
        } else {
            accessibilityManager.enableMonitoring()
        }
    }

    private func computeStats() -> QuickStats {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todaysSuggestions = suggestions.filter {
            $0.model.createdAt >= today
        }
        let riskKeywords = ["Risk", "Sanit"]
        let risksCaught = todaysSuggestions.filter { suggestion in
            riskKeywords.contains { keyword in
                suggestion.model.suggestionType.localizedCaseInsensitiveContains(keyword)
            }
        }.count
        let improved = todaysSuggestions.count - risksCaught
        return QuickStats(
            promptsToday: todaysSuggestions.count,
            risksCaught: risksCaught,
            promptsImproved: max(improved, 0)
        )
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Shield Status Card (PS-07)

private struct ShieldStatusCard: View {
    let isActive: Bool
    let awaitingPermission: Bool
    let pulse: Bool
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PSSpacing.xl) {
            HStack(alignment: .center, spacing: PSSpacing.xl) {
                iconWrap
                VStack(alignment: .leading, spacing: PSSpacing.xs) {
                    Text(isActive ? "Promptly is on" : "Promptly")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.psText)
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.psText2)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                statusTag
            }

            activateButton
        }
        .padding(PSSpacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.xl, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
    }

    private var description: String {
        if awaitingPermission {
            return "Grant accessibility permission to start monitoring your prompts."
        }
        return isActive
            ? "Monitoring prompts across your AI tools"
            : "Activate to start monitoring your prompts across apps"
    }

    @ViewBuilder
    private var iconWrap: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                .fill(isActive ? Color.psBlueLight : Color.psBg2)
                .overlay(
                    RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                        .stroke(isActive ? Color.psBlue : Color.psText3.opacity(0.5), lineWidth: 1)
                )
                .frame(width: 56, height: 56)
            Image(systemName: "shield.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(isActive ? Color.psBlue : Color.psText3)
        }
    }

    @ViewBuilder
    private var statusTag: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.psGreen : Color.psText3)
                .frame(width: 6, height: 6)
                .opacity(isActive && pulse ? 0.4 : 1.0)
                .animation(
                    isActive
                        ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
            Text(isActive ? "Active" : "Inactive")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Color.psGreen : Color.psText3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActive ? Color.psGreenLight : Color.psBg3)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var activateButton: some View {
        Button {
            onPrimaryAction()
            // Q1: when the tour spotlights this button with
            // interactionAllowed=true, clicking it auto-advances to the
            // next step. Noop when no tour is active.
            TourCoordinator.shared.userPerformedAnchorAction()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(textColor)
            .background(background)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(borderColor, lineWidth: 1)
            )
            .shadow(
                color: isActive ? .clear : Color.psBlue.opacity(0.32),
                radius: 4, x: 0, y: 2
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: awaitingPermission)
        .accessibilityLabel(label)
        .tourAnchor("control-panel-activate-button")
    }

    private var label: String {
        if awaitingPermission { return "Grant permission →" }
        return isActive ? "Turn off" : "Turn on Promptly"
    }

    private var textColor: Color {
        if awaitingPermission { return .white }
        return isActive ? Color.psText3 : .white
    }

    private var background: Color {
        if awaitingPermission { return Color.psAmber }
        return isActive ? Color.psBg3 : Color.psBlue
    }

    private var borderColor: Color {
        if awaitingPermission { return Color.psAmber }
        return isActive ? Color.psBorder2 : Color.psBlue
    }

    private var dotColor: Color {
        if awaitingPermission { return .white.opacity(0.8) }
        return isActive ? Color.psGreen : .white.opacity(0.7)
    }
}

// MARK: - Permission Banner (PS-08)

private struct PermissionBanner: View {
    let onSetup: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: PSSpacing.md) {
            Image(systemName: "lock.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.psAmber)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility permission needed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.psAmber)
                Text("Promptly needs this to detect text fields in AI tools. We only read text you're about to send — nothing else is accessed.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.psAmber.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: PSSpacing.md)

            Button(action: onSetup) {
                Text("Set up →")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.psAmber)
                    .clipShape(RoundedRectangle(cornerRadius: PSRadius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PSSpacing.lg)
        .padding(.vertical, 14)
        .background(Color.psAmberLight)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                .stroke(Color.psAmberBorder, lineWidth: 1)
        )
    }
}

// MARK: - Quick Stats

private struct QuickStats {
    let promptsToday: Int
    let risksCaught: Int
    let promptsImproved: Int
}

private struct QuickStatsRow: View {
    let stats: QuickStats

    var body: some View {
        HStack(spacing: PSSpacing.lg) {
            StatCard(icon: "bubble.left.and.bubble.right.fill", iconColor: Color.psBlue,
                     value: "\(stats.promptsToday)", label: "Prompts today")
            StatCard(icon: "shield.lefthalf.filled", iconColor: Color.psRed,
                     value: "\(stats.risksCaught)", label: "Risks caught")
            StatCard(icon: "sparkles", iconColor: Color.psGreen,
                     value: "\(stats.promptsImproved)", label: "Prompts improved")
        }
    }
}

private struct StatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.psText)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.psText3)
        }
        .padding(PSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Suggestion Overview Section

private struct SuggestionOverviewSection: View {
    let types: [SuggestionType]
    let onOpenSettings: () -> Void

    private var enabledTypes: [SuggestionType] {
        types.filter { $0.model.isEnabled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PSSpacing.md) {
            HStack {
                Text("Suggestion Types")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.psText2)
                Spacer()
                Button(action: onOpenSettings) {
                    Text("Manage in Settings →")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.psBlue)
                }
                .buttonStyle(.plain)
            }

            if enabledTypes.isEmpty {
                Text("No suggestion types enabled. Open Settings to enable the ones you need.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.psText3)
                    .padding(PSSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                            .stroke(Color.psBorder, lineWidth: 1)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(enabledTypes.prefix(6).enumerated()), id: \.element.model.uuid) { index, type in
                        SuggestionOverviewRow(type: type, isLast: index == min(5, enabledTypes.count - 1))
                    }
                }
                .background(Color.psSurface)
                .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                        .stroke(Color.psBorder, lineWidth: 1)
                )
            }
        }
    }
}

private struct SuggestionOverviewRow: View {
    let type: SuggestionType
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: PSSpacing.md) {
                Text(SuggestionTypeCatalog.metadata(for: type)?.emoji ?? "✨")
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.model.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.psText)
                    if let summary = SuggestionTypeCatalog.metadata(for: type)?.summary
                        ?? (type.model.description.isEmpty ? nil : type.model.description) {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.psText3)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Circle()
                    .fill(Color.psGreen)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, PSSpacing.lg)
            .padding(.vertical, 12)

            if !isLast {
                Divider().background(Color.psBorder)
            }
        }
    }
}
