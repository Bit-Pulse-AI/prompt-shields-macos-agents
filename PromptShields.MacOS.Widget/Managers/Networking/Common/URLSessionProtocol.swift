import Foundation

/// Protocol for URL session operations to enable testing
protocol URLSessionProtocol: Sendable {
    /// Performs a data task with the given request
    /// - Parameter request: The URL request to execute
    /// - Returns: Data task result with data, response, and error
    func dataTask(with request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {
    func dataTask(with request: URLRequest) async throws -> (Data, URLResponse) {
        return try await data(for: request)
    }
}
