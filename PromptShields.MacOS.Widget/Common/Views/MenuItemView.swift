import SwiftUI

struct MenuItemView: View {
    private let title: String
    private let imageName: String
    private let action: (() -> Void)?

    init(imageName: String, title: String, action: (() -> Void)? = nil) {
        self.imageName = imageName
        self.title = title
        self.action = action
    }
    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 8) {
                Image(ImageResource(name: imageName, bundle: .main))
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(NSFont.body2.swiftUIFont)
                    .foregroundStyle(Color.onSurface)
            }
        }
    }
}
