import Foundation

/// Protocol for JSON encoding/decoding operations to enable testing
protocol JSONCodingProtocol: Sendable {
    /// Encodes an object to JSON data
    /// - Parameter value: The object to encode
    /// - Returns: Encoded JSON data
    /// - Throws: Encoding errors if the object cannot be encoded
    func encode<T: Encodable>(_ value: T) throws -> Data
    
    /// Decodes JSON data to an object
    /// - Parameters:
    ///   - type: The type to decode to
    ///   - data: The JSON data to decode
    /// - Returns: Decoded object
    /// - Throws: Decoding errors if the data cannot be decoded
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
} 
