enum StringErrors: Error {
    case invalidStringToData
    var errorDescription: String? {
        switch self {
        case .invalidStringToData:
            return "Failed to convert string to data"
        }
    }
}
