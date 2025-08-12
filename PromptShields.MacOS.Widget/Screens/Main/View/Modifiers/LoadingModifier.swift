import SwiftUI

struct LoadingModifier: ViewModifier {
    let isLoading: Bool
    
    func body(content: Content) -> some View {
        if isLoading {
            ZStack {
                content
                VStack(alignment: .center, spacing: .zero) {
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(.black.opacity(0.4))
            }
        } else {
            content
        }
    }
}
