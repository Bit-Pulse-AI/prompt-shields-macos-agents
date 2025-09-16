struct NetworkError: Error {
    let message: String
    let statusCode: Int?
    
    init(message: String, statusCode: Int? = nil) {
        self.message = message
        self.statusCode = statusCode
    }
    
    static func invalidResponse(message: String) -> NetworkError {
        return NetworkError(message: message)
    }
    
    var isUnauthorized: Bool {
        return statusCode == 401 || statusCode == 403
    }
}
