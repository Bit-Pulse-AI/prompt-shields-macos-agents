struct NetworkError: Error {
    let message: String
    
    static func invalidResponse(message: String) -> NetworkError {
        return NetworkError(message: message)
    }
}
