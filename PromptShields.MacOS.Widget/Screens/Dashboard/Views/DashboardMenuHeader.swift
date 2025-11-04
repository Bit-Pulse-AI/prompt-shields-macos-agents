import SwiftUI

struct DashboardMenuHeaderView: View {
    @EnvironmentObject private var dashboardState: DashboardStateModel

    var logo: some View {
        HStack(spacing: .zero) {
            Image(ImageResource(name: "large_logo", bundle: .main))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 32)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(spacing: .zero) {
            logo
                .padding(.bottom, 10)
        }
    }
}
