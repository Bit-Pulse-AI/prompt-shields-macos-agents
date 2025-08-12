import SwiftUI

struct UserInfoView: View {
    @EnvironmentObject private var dashboardState: DashboardStateModel
    @Environment(\.userDomainService) private var userDomainService
    @State var name: String = "n/a"
    @State var photoURL: URL?
    
    var body: some View {
        Button {
            dashboardState.contentState = .account
        } label: {
            HStack(spacing: .zero) {
                RoundCirclePortraitView(url: $photoURL, lineWidth: 1)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.gray)
                Text(name)
                    .foregroundStyle(Color.onBackground)
                    .font(NSFont.body2.swiftUIFont)
                    .padding(.leading, 8)
                Spacer()
            }.frame(alignment: .center)
        }
        .buttonStyle(.plain)
        .task {
            guard let currentUser = try? await userDomainService.currentUser else {
                return
            }
            name = currentUser.model.firstName + " " + currentUser.model.lastName
            photoURL = currentUser.model.photoURL
        }
    }
}
