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
        Task {
            shouldShowProgressView = true
            try? await userDomainService.logout()
            try await userDomainService.deleteAll()
            await MainActor.run {
                globalMainStateModel.authState = .loggedOut(nil)
                shouldShowProgressView = false
            }
            shouldShowProgressView = false
        }
    }

    private func acceptTermsAndConditions() {
        Task {
            do {
                shouldShowProgressView = true
                let currentUser = try await userDomainService.currentUser(refresh: true)
                let profile = try await profileDomainService.acceptTermsAndConditions()

                let shaId = try currentUser.model.uuid.sha512
                if profile.model.acceptedTerms == shaId {
                    await MainActor.run {
                        globalMainStateModel.authState = .loggedIn
                    }
                } else {
                    await MainActor.run {
                        globalMainStateModel.authState = .acceptTerms
                    }
                }
            } catch {
                await MainActor.run {
                    isAlertPresented = true
                }
            }
        }
    }

    private func declineTermsAndConditions() {
        logout()
    }

    private func handleTokenRefreshFailure() {
        Task {
            do {
                try await userDomainService.logout()

                await MainActor.run {
                    globalMainStateModel.authState = .loggedOut(AuthError.tokenRefreshFailed)
                }
            } catch {
                await MainActor.run {
                    globalMainStateModel.authState = .loggedOut(error)
                }
            }
        }
    }
}
