import Foundation

enum CheckoutDecodeError: Error {
    case invalidURL
}

struct Checkout {
    let url: URL
    let sessionId: String
    let customerId: String
    let expiresAt: Date
}

struct CheckoutAPIResponse: SendableDecodable {
    let url: String
    let sessionId: String
    let customerId: String
    let expiresAt: Int

    enum CodingKeys: String, CodingKey {
        case url = "checkout_url"
        case sessionId = "session_id"
        case customerId = "customer_id"
        case expiresAt = "expires_at"
    }

    func toDomain() throws -> Checkout {
        guard let url = URL(string: url) else {
            throw CheckoutDecodeError.invalidURL
        }
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        return Checkout(url: url,
                        sessionId: sessionId,
                        customerId: customerId,
                        expiresAt: expiresAt)
    }
}
