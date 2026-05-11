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
    @State private var showOnboarding: Bool = false

    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @Environment(\.profileDomainService) private var profileDomainService
    @Environment(\.userDomainService) private var userDomainService

    var body: some View {
        VStack {
            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(globalMainStateModel)
        // Q5: cross-window chat-button step. We anchor an invisible 1×1
        // marker to the bottom-right corner of the dashboard window; the
        // coachmark points at it so the user knows to look there for the
        // floating chat icon (which lives in a separate window). Avoids
        // the spotlight-across-windows complexity.
        .overlay(alignment: .bottomTrailing) {
            Color.clear
                .frame(width: 1, height: 1)
                .padding(.bottom, 8)
                .padding(.trailing, 8)
                .tourAnchor("off-window-chat-hint")
        }
        // Tour overlay for the dashboard window. Renders backdrop +
        // spotlight + coachmark whenever the active step's anchor is
        // inside this view hierarchy.
        .tourOverlay()
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
        // First-launch onboarding sheet (PS-04). Lives at the MainView
        // level so step 4 can mutate globalMainStateModel.authState
        // when the merged login button succeeds.
        .onAppear {
            if !OnboardingPersistence.hasCompleted {
                showOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
            showOnboarding = true
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .devSkipLogin)) { _ in
            // Dev shortcut: pretend Auth0 succeeded so QA can reach the
            // dashboard. Real user fetch will fail — Account / Suggestions
            // will be empty — but the UI surface is exercisable.
            globalMainStateModel.authState = .loggedIn
            showOnboarding = false
        }
        #endif
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .environmentObject(accessibilityManager)
                .environmentObject(globalMainStateModel)
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
            try? await AuthenticationManagerImpl.shared.logout()
            globalMainStateModel.authState = .loggedOut(nil)
            shouldShowProgressView = false
        }
    }

    private func acceptTermsAndConditions() {
        Task { @MainActor in
            do {
                shouldShowProgressView = true
                let currentUser = try await userDomainService.currentUser
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
            try? await AuthenticationManagerImpl.shared.logout()
            globalMainStateModel.authState = .loggedOut(AuthError.tokenRefreshFailed)
        }
    }
}
