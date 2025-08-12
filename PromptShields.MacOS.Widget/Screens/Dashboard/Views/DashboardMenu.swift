import SwiftUI

struct DashboardMenuView: View {
    @EnvironmentObject private var dashboardState: DashboardStateModel
    
    var body: some View {
        HStack(alignment: .center, spacing: .zero) {
            Button {
                withAnimation {
                    $dashboardState.isSideMenuCollapsed.wrappedValue.toggle()
                }
            } label: {
                Image(ImageResource(name: "split_view_toggle", bundle: .main))
            }
            .buttonStyle(.plain)
            Spacer()
//            Button {
//                $dashboardState.isSearchVisible.wrappedValue.toggle()
//            } label: {
//                Image(ImageResource(name: "search", bundle: .main))
//            }
            .padding(.top, 2)
            .buttonStyle(.plain)
        }.frame(alignment: .center)
    }
}
