import Foundation

extension Data {
    func decode<T: Decodable>() throws -> T {
        // Decode response
        let decoder = createJSONDecoder()
        let map = try decoder.decode(Response<T>.self, from: self)
//        TODO: Add mapping
        return map.content
    }

    /// Creates a JSON decoder with custom date formatting
    /// - Returns: Configured JSONDecoder
    private func createJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        dateFormatter.timeZone = TimeZone.current
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        return decoder
    }
}
