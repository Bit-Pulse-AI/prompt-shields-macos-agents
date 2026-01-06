extension Sequence {
    func asyncCompactMap<T>(
        _ transform: @escaping (Element) async throws -> T?
    ) async throws -> [T] {
        var results = [T]()

        for element in self {
            if let transformed = try await transform(element) {
                results.append(transformed)
            }
        }

        return results
    }
}
