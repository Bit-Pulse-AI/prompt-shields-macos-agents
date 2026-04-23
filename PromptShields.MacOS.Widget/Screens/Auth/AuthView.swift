import SwiftUI
import os

struct AuthView: View {
    @EnvironmentObject private var mainState: MainStateModel

    private let loginButtonStyle = AccountButtonStyle(
        foregroundColor: Color.primary,
        backgroundColor: .white,
        borderColor: .border,
        cornerRadius: 8
    )

    private let logger: os.Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AuthView.self)
    )

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(ImageResource(name: "large_logo", bundle: .main))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 100)
            if mainState.isBusy {
                ProgressView()
            } else {
                Button {
                    Task { @MainActor in
                        mainState.isBusy = true
                        await performLogin()
                        mainState.isBusy = false
                    }
                } label: {
                    Text("Log in")
                }.buttonStyle(loginButtonStyle)
            }
        }.frame(maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center)
    }

    @MainActor
    private func performLogin() async {
        do {
            let state = try await AuthenticationManagerImpl.shared.login()
            mainState.authState = state
        } catch {
            logger.debug("Login failed: \(error.localizedDescription)")
        }
    }
}
