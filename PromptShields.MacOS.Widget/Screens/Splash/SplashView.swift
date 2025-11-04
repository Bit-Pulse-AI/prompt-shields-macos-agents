import SwiftUI
import os

struct SplashView: View {
    @EnvironmentObject var mainState: MainStateModel
    @Environment(\.userDomainService) private var userDomainService
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
            Image(ImageResource(name: "logo", bundle: .main))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 120)
                ProgressView()
        }
        .frame(maxWidth: .infinity,
               maxHeight: .infinity,
               alignment: .center)
        .onAppear {
            checkAuth()
        }
    }

    func checkAuth() {
        Task { @MainActor in
            do {
                _ = try await userDomainService.currentUser
                mainState.authState = .loggedIn
            } catch {
                mainState.authState = .loggedOut(error)
            }
        }
    }
}
