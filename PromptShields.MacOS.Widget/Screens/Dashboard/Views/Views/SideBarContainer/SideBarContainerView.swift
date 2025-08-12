import SwiftUI

struct SideBarContainerView<FullSideBarView: View,
                            ChannelDetailInfoView: View,
                            CompactSideBarMakeView: View,
                            ChevronButtonMakeView: View>: View {
    @Binding private var sidebarWidth: CGFloat
    
    private let fullSideBarMakeView: () -> FullSideBarView
    private let userDetailInfoMakeView: () -> ChannelDetailInfoView
    private let compactSideBarMakeView: () -> CompactSideBarMakeView
    private let chevronButtonMakeView: () -> ChevronButtonMakeView
    
    init(sidebarWidth: Binding<CGFloat>,
         fullSideBarMakeView: @escaping () -> FullSideBarView,
         userDetailInfoMakeView: @escaping () -> ChannelDetailInfoView,
         compactSideBarMakeView: @escaping () -> CompactSideBarMakeView,
         chevronButtonMakeView: @escaping () -> ChevronButtonMakeView) {
        self._sidebarWidth = sidebarWidth
        self.fullSideBarMakeView = fullSideBarMakeView
        self.userDetailInfoMakeView = userDetailInfoMakeView
        self.compactSideBarMakeView = compactSideBarMakeView
        self.chevronButtonMakeView = chevronButtonMakeView
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            if sidebarWidth > 110 {
                fullSideBarMakeView()
                    .padding(.horizontal, 16)
                Divider()
                    .foregroundStyle(Color.gray)
                userDetailInfoMakeView()
                    .padding(.horizontal, 16)
            } else {
                compactSideBarMakeView()
            }
        }
        .frame(minWidth: 64, maxWidth: sidebarWidth)
        .clipped()
        .background(.white)

        if sidebarWidth <= 110 {
            chevronButtonMakeView()
        }
    }
}
