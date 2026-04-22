import SwiftUI

// Persistent topbar across all dashboard screens. Informational only —
// activation is controlled from the Control Panel status card (PS-07).

@MainActor
struct DashboardContentHeaderView: View {
    @EnvironmentObject private var dashboardState: DashboardStateModel
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl

    private var isActive: Bool {
        accessibilityManager.monitoringState == .enabled
    }

    var body: some View {
        HStack(spacing: PSSpacing.md) {
            Text("Prompt Shields")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.psText)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(isActive ? Color.psGreen : Color.psBorder2)
                    .frame(width: 6, height: 6)
                Text(isActive ? "Shield active" : "Shield inactive")
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? Color.psGreen : Color.psText3)
            }
        }
        .padding(.horizontal, PSSpacing.xxl)
        .padding(.vertical, 10)
        .frame(height: 44)
        .background(Color.psBg2)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.psBorder),
            alignment: .bottom
        )
    }
}
