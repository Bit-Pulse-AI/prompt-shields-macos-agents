import SwiftUI

struct RoundCirclePortraitView: View {
    @Binding private var url: URL?
    private let lineWidth: CGFloat
    @State private var cachedImage: Image?
    
    func photo(size: CGSize) -> some View {
        VStack(alignment: .center, spacing: .zero) {
            Image(systemName: "photo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.gray)
                .frame(width: size.width, height: size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity,
               maxHeight: .infinity,
               alignment: .center)
    }
    var body: some View {
        GeometryReader { geometry in
            if let url = url {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .success(let cgImage):
                        let imageAspectRatio = CGFloat(cgImage.width) / CGFloat(cgImage.height)
                        let containerAspectRatio = geometry.size.width / geometry.size.height
                        
                        Canvas { context, size in
                            let drawRect: CGRect
                            
                            if imageAspectRatio > containerAspectRatio {
                                // Image is wider than the container
                                let scaledHeight = size.width / imageAspectRatio
                                drawRect = CGRect(
                                    x: 0,
                                    y: (size.height - scaledHeight) / 2,
                                    width: size.width,
                                    height: scaledHeight
                                )
                            } else {
                                // Image is taller than the container
                                let scaledWidth = size.height * imageAspectRatio
                                drawRect = CGRect(
                                    x: (size.width - scaledWidth) / 2,
                                    y: 0,
                                    width: scaledWidth,
                                    height: size.height
                                )
                            }
                            
                            context.draw(Image(decorative: cgImage, scale: 1.0), in: drawRect)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    case .failure:
                        Text("Failed to load image")
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(lineWidth: lineWidth)
                        .foregroundStyle(.white)
                        .background(.clear)
                }
            } else {
                photo(size: geometry.size.scaled(scale: 0.5))
            }
        }
    }
    
    private func cacheImage(image: Image) {
        cachedImage = image
    }
    
    init(url: Binding<URL?>, lineWidth: CGFloat = 1) {
        self._url = url
        self.lineWidth = lineWidth
    }
}
