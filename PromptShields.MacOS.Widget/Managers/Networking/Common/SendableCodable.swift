import Foundation

protocol SendableCodable: Sendable & Codable {}
protocol SendableDecodable: Sendable & Decodable {}
protocol SendableEncodable: Sendable & Encodable {}
