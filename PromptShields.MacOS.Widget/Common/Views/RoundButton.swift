import SwiftUI

struct RoundButton: View {
    let assetName: String
    let backgroundColor: Color
    let borderColor: Color
    let iconColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .center) {
                Circle()
                    .stroke(style: .init(lineWidth: 1))
                    .foregroundStyle(borderColor)
                    .background(backgroundColor)
                    .frame(width: 40, height: 40)
                Image(ImageResource(name: assetName, bundle: .main))
                    .renderingMode(.template)
                    .foregroundStyle(iconColor)
                    .frame(width: 16, height: 16)
            }
            .clipShape(Circle())
            .frame(alignment: .center)
        }
        .buttonStyle(.plain)
    }
}
