import SwiftUI
import os

final class AuthStateModel: ObservableObject {
    @Published var isBusy: Bool = false
}

struct AuthView: View {
    @EnvironmentObject private var mainState: MainStateModel
    @Environment(\.userDomainService) private var userDomainService
    @Environment(\.profileDomainService) private var profileDomainService

    private let loginButtonStyle = AccountButtonStyle(foregroundColor: Color.primary,
                                                      backgroundColor: .white,
                                                      borderColor: .border,
                                                      cornerRadius: 8)

    private let logger: os.Logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AuthView.self)
    )

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(ImageResource(name: "logo", bundle: .main))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 120)
            if mainState.isBusy {
                ProgressView()
            } else {
                Button {
                    Task {
                        await MainActor.run {
                            mainState.isBusy = true
                        }
                        await authenticateRegisterUser()
                        await MainActor.run {
                            mainState.isBusy = false
                        }
                    }
                } label: {
                    Text("Log me in")
                }.buttonStyle(loginButtonStyle)
            }
        }.frame(maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center)
    }

    func authenticateRegisterUser() async {
        do {
            let user = try await userDomainService.login()
            let profile = try await profileDomainService.currentProfile(refresh: true)

            let shaId = try user.model.uuid.sha512
            if profile.model.acceptedTerms == shaId {
                await MainActor.run {
                    mainState.authState = .loggedIn
                }
            } else {
                await MainActor.run {
                    mainState.authState = .acceptTerms
                }
            }
        } catch {
            logger.error("Error encountered \(error)")
        }
    }
}
