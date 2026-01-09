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
    @State private var shouldShowProgressView: Bool = false
    @State private var isAlertPresented: Bool = false
    @State private var alertMessage: String = ""

    @Environment(\.userDomainService) private var userDomainService
    @Environment(\.profileDomainService) private var profileDomainService

    var body: some View {
        VStack {
            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(globalMainStateModel)
        .onReceive(NotificationCenter.default.publisher(for: .tokenRefreshFailed)) { _ in
            handleTokenRefreshFailure()
        }
        .alert("Failed accepting terms and conditions. Please try again", isPresented: $isAlertPresented) {
            Button("OK", role: .cancel) {
                Task {
                    logout()
                }
            }
        }
    }

    @ViewBuilder
    private var progressView: some View {
        HStack(alignment: .center, spacing: .zero) {
            ProgressView()
        }
        .frame(maxWidth: .infinity,
               maxHeight: .infinity,
               alignment: .center)
    }

    @ViewBuilder
    private var contentView: some View {
        switch globalMainStateModel.authState {
        case .loggedIn:
            DashboardView()
        case .acceptTerms:
            if shouldShowProgressView {
                progressView
            } else {
                TermsAndConditionsView(termsText:
                                        String
                    .stringFromBundleFile(named: "terms_and_conditions",
                                          extension: "md"),
                                       onAccept: {
                                            acceptTermsAndConditions()
                                       },
                                       onDecline: {
                                            declineTermsAndConditions()
                                       }
                )
            }
        case .loggedOut:
            AuthView()
        case .undetermined:
            SplashView()
        }
    }

    private func logout() {
        Task { @MainActor in
            shouldShowProgressView = true
            try? await userDomainService.logout()
            try? await userDomainService.deleteAll()
            globalMainStateModel.authState = .loggedOut(nil)
            shouldShowProgressView = false
        }
    }

    private func acceptTermsAndConditions() {
        Task { @MainActor in
            do {
                shouldShowProgressView = true
                let currentUser = try await userDomainService.currentUser(refresh: true)
                let profile = try await profileDomainService.acceptTermsAndConditions()

                let shaId = try currentUser.model.uuid.sha512
                if profile.model.acceptedTerms == shaId {
                    globalMainStateModel.authState = .loggedIn
                } else {
                    globalMainStateModel.authState = .acceptTerms
                }
            } catch {
                isAlertPresented = true
            }
            shouldShowProgressView = false
        }
    }

    private func declineTermsAndConditions() {
        logout()
    }

    private func handleTokenRefreshFailure() {
        Task { @MainActor in
            do {
                try await userDomainService.logout()
                globalMainStateModel.authState = .loggedOut(AuthError.tokenRefreshFailed)
            } catch {
                globalMainStateModel.authState = .loggedOut(error)
            }
        }
    }
}
