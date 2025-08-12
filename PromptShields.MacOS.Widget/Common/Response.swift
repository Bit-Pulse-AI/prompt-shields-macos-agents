struct Response<T: Decodable>: Decodable {
    let content: T
    let status_code: Int
    let message: String?
    let error: String?
    let success: Bool
}
