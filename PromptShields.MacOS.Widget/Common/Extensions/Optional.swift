import Foundation

/// Extension to provide logging-friendly string representations of optional values
extension Optional {
    /// Returns a string representation suitable for logging
    var loggable: String {
        if let safe = self {
            return "\(safe)"
        } else {
            return "nil"
        }
    }
}

extension Optional<String> {
    var url: URL? {
        if let self = self {
            return URL(string: self)
        } else {
            return nil
        }
    }
}
/// Extension to convert optional Data to String
extension Optional<Data> {
    /// Converts Data to String using UTF-8 encoding
    var string: String? {
        if let safe = self {
            return String(data: safe, encoding: .utf8)
        } else {
            return nil
        }
    }
}
