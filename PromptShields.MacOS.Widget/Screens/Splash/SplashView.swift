import SwiftUI
import os

struct SplashView: View {
    @EnvironmentObject var mainState: MainStateModel
    @Environment(\.userDomainService) private var userDomainService
    @Environment(\.profileDomainService) private var profileDomainService
    private let loginButtonStyle = AccountButtonStyle(foregroundColor: Color.primary,
                                                        backgroundColor: .white,
                                                        borderColor: .border,
                                                        cornerRadius: 8)
    private let logger: os.Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SplashView.self)
    )

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(ImageResource(name: "large_logo", bundle: .main))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 100)
                ProgressView()
        }
        .frame(maxWidth: .infinity,
               maxHeight: .infinity,
               alignment: .center)
        .onAppear {
            checkAuth()
        }
    }

    private func checkAuth() {
        Task { @MainActor in
            do {
                let profile = try await profileDomainService.currentProfile
                let shaId = try profile.model.userId.sha512
                if profile.model.acceptedTerms == shaId {
                    mainState.authState = .loggedIn
                } else {
                    mainState.authState = .acceptTerms
                }
            } catch {
                mainState.authState = .loggedOut(error)
            }
        }
    }
}
