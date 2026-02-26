import SwiftUI
import os

struct SplashView: View {
    @EnvironmentObject var mainState: MainStateModel

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
            let state = await AuthenticationManagerImpl.shared.validateSession()
            logger.debug("Session validation result: \(String(describing: state))")
            mainState.authState = state
        }
    }
}
