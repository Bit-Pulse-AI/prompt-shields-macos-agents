import SwiftUI

struct ChannelToolbarViewModel {
    let id: String = UUID().uuidString
    let title: String
    let icon: Image

    let action: () -> Void
}

struct LLMButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
                .font(NSFont.body3.swiftUIFont)
                .foregroundStyle(.black)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.white)
        .cornerRadius(8)
        .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
        .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct ChannelToolbarView: View {
    let items: [ChannelToolbarViewModel]
    let addAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.id) { item in
                Button {
                    item.action()
                } label: {
                    Label(title: {
                        Text(item.title)
                    }, icon: {
                        item.icon.frame(width: 24, height: 24)
                    })
                }
                .buttonStyle(LLMButtonStyle())
            }
            Button {
                self.addAction()
            } label: {
                Image(ImageResource(name: "big_plus", bundle: .main))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
        Divider()
            .padding(.vertical, 16)
    }
}
