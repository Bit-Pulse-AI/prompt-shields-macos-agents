import SwiftUI

struct MultiRoundCirclePortraitView: View {
    struct RoundCircleItem: Identifiable {
        var id: String = UUID().uuidString
        let url: URL
    }
    private let maxNumberOfItems = 2
    private let overlap: CGFloat = 5
    let items: [RoundCircleItem]
    let portraitSize: CGSize = .init(width: 20, height: 20)
    
    var numberOfItems: Int {
        min(maxNumberOfItems, items.count)
    }
    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(0..<numberOfItems, id: \.self) { index in
                let item = items[index]
                RoundCirclePortraitView(url: Binding(get: { item.url }, set: { _ in }) )
                    .frame(width: portraitSize.width, height: portraitSize.height)
            }
            if items.count > maxNumberOfItems {
                ZStack(alignment: .center) {
                    Capsule()
                        .fill(Color.border)
                        .stroke(.white, style: .init(lineWidth: 1))
                        .foregroundStyle(Color.border)
                        .frame(width: 35, height: 20)
                    Text("+ \(Int(CGFloat(items.count) - CGFloat(maxNumberOfItems)))")
                        .font(NSFont.body3.swiftUIFont)
                        .foregroundStyle(Color.onSurface)
                }
                .frame(alignment: .center)
            }
        }.frame(alignment: .leading)
    }
}
