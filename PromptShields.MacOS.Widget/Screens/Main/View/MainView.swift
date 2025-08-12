import SwiftUI

final class MainStateModel: ObservableObject {
    @Published var isBusy: Bool = false
    @Published var authState: AuthState = .undetermined
    @Published var popupType: PopupType?
}

struct MainView: View {
    @StateObject private var globalMainStateModel = MainStateModel()
    @StateObject private var overlayStateObject: OverlayStateModel
    
    init(overlayStateObject: StateObject<OverlayStateModel>) {
        self._overlayStateObject = overlayStateObject
    }
    var body: some View {
        VStack {
            contentView
                .showLoading(isLoading: globalMainStateModel.isBusy)
                .overlay {
                    EmptyView()
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(globalMainStateModel)
    }
    
    @ViewBuilder
    var contentView: some View {
        switch globalMainStateModel.authState {
        case .loggedIn:
            DashboardView(overlayStateModel: _overlayStateObject)
        case .loggedOut:
            AuthView()
        case .undetermined:
            SplashView()
        }
    }
}
