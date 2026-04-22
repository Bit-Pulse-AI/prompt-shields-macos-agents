import SwiftUI

struct DashboardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .font(NSFont.body3.swiftUIFont)
                .foregroundColor(.black)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.border, lineWidth: 1)
        )
        .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
        .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct DashboardSidebarView: View {
    @EnvironmentObject private var dashboardState: DashboardStateModel
    @Environment(\.userDomainService) private var userDomainService
    @State var accountPhoto: URL?
    private let buttonStyle = DashboardButtonStyle()

    var body: some View {
        SideBarContainerView(sidebarWidth: Binding(get: {
            DashboardViewParameters.sidebarWidth(isCollapsed: dashboardState.isSideMenuCollapsed)
        }, set: { _ in })) {
            VStack {
                DashboardMenuHeaderView()
                DashboardMenuView()

                Button {
                    dashboardState.contentState = .controlPanel
                } label: {
                    Text("Control Panel")
                }
                .padding(.top, 16)
                .buttonStyle(buttonStyle)
                Button {
                    dashboardState.contentState = .suggestions
                } label: {
                    Text("Activity Log")
                }
                .buttonStyle(buttonStyle)
                Button {
                    dashboardState.contentState = .settings
                } label: {
                    Text("Settings")
                }
                .buttonStyle(buttonStyle)
                Spacer()
            }
        } userDetailInfoMakeView: {
            userInfoView
        } compactSideBarMakeView: {
            compactSidebar
        } chevronButtonMakeView: {
            chevronButton
        }
        .task {
            accountPhoto = try? await userDomainService.currentUser.model.photoURL
        }
    }

    @ViewBuilder
    private var userInfoView: some View {
        UserInfoView()
            .padding(.vertical, 24)
    }

    @ViewBuilder
    private var compactSidebar: some View {
        compactLogo
            .padding(.horizontal, 16)
        Spacer()
        Divider()
            .foregroundStyle(Color.gray)
            .padding(.vertical, 16)
        RoundCirclePortraitView(url: $accountPhoto, lineWidth: 1)
            .frame(width: 32, height: 32)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .foregroundStyle(.gray)
    }

    private var compactLogo: some View {
        HStack(spacing: .zero) {
            Image(ImageResource(name: "logo_mid", bundle: .main))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(x: 1, y: 1)
    }

    private var chevronButton: some View {
        ChevronButton(isCollapsed: $dashboardState.isSideMenuCollapsed)
    }
}
