import SwiftUI
import Combine

/// A SwiftUI-only `AsyncImage` replacement with disk-based caching via `URLCache`.
struct CachedAsyncImage<Content: View>: View {
    private let url: URL
    private let content: (AsyncImagePhase) -> Content
    @StateObject private var loader: ImageLoader

    init(
        url: URL,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.content = content
        _loader = StateObject(wrappedValue: ImageLoader(url: url))
    }

    var body: some View {
        content(loader.phase)
            .onAppear { loader.load() }
    }
}

/// Represents the state of the image loading process.
enum AsyncImagePhase {
    case empty
    case success(CGImage)
    case failure(Error)
}

/// A SwiftUI loader for fetching and caching images with `URLCache`.
final class ImageLoader: ObservableObject {
    @Published var phase: AsyncImagePhase = .empty

    private static let cache = URLCache.shared // Shared URLCache
    private let url: URL
    private var cancellables = Set<AnyCancellable>()

    init(url: URL) {
        self.url = url
    }

    func load() {
        // Check if the response is already cached
        if let cachedResponse = Self.cache.cachedResponse(for: URLRequest(url: url)),
           let image = createCGImage(from: cachedResponse.data) {
            // Serve the cached image
            self.phase = .success(image)
            return
        }

        // Fetch image from network
        phase = .empty
        URLSession.shared.dataTaskPublisher(for: url)
            .handleEvents(receiveOutput: { data, response in
                // Cache the response for future use
                if let response = response as? HTTPURLResponse,
                   response.statusCode == 200 {
                    let cachedResponse = CachedURLResponse(response: response, data: data)
                    Self.cache.storeCachedResponse(cachedResponse, for: URLRequest(url: self.url))
                }
            })
            .tryMap { output -> CGImage in
                guard let image = createCGImage(from: output.data) else {
                    throw URLError(.cannotDecodeContentData)
                }
                return image
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.phase = .failure(error)
                    }
                },
                receiveValue: { [weak self] image in
                    self?.phase = .success(image)
                }
            )
            .store(in: &cancellables)
    }
}

/// Helper function to create a `CGImage` from raw data.
private func createCGImage(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}
