import SwiftUI
import Combine

@MainActor
final class MainStateModel: ObservableObject {
    @Published var isBusy: Bool = false
    @Published var authState: AuthState = .undetermined
    @Published var popupType: PopupType?
}

struct MainView: View {
    @StateObject private var globalMainStateModel = MainStateModel()
    @Environment(\.userDomainService) private var userDomainService

    var body: some View {
        VStack {
            contentView
                .showLoading(isLoading: globalMainStateModel.isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(globalMainStateModel)
        .onReceive(NotificationCenter.default.publisher(for: .tokenRefreshFailed)) { _ in
            handleTokenRefreshFailure()
        }
    }

    @ViewBuilder
    var contentView: some View {
        switch globalMainStateModel.authState {
        case .loggedIn:
            DashboardView()
        case .loggedOut:
            AuthView()
        case .undetermined:
            SplashView()
        }
    }

    private func handleTokenRefreshFailure() {
        Task {
            do {
                await MainActor.run {
                    globalMainStateModel.isBusy = true
                }

                try await userDomainService.logout()

                await MainActor.run {
                    globalMainStateModel.authState = .loggedOut(AuthError.tokenRefreshFailed)
                    globalMainStateModel.isBusy = false
                }
            } catch {
                await MainActor.run {
                    globalMainStateModel.authState = .loggedOut(error)
                    globalMainStateModel.isBusy = false
                }
            }
        }
    }
}
