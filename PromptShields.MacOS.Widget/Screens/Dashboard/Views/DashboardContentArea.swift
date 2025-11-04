import SwiftUI

struct DashboardContentAreaView: View {
    @EnvironmentObject private var mainState: MainStateModel
    @EnvironmentObject private var dashboardState: DashboardStateModel

    var body: some View {
        VStack(spacing: .zero) {
            DashboardContentHeaderView()
            switch dashboardState.contentState {
            case .controlPanel:
                ControlPanelView()
            case .settings:
                SettingsView()
            case .suggestions:
                SuggestionsView()
            case .account:
                AccountView()
            }
        }
    }
}
