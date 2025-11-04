import Foundation

extension URL {
    var encrypt: String {
        get throws {
            absoluteString.encrypt
        }
    }

    init?(string: String?) {
        guard let string else {
             return nil
        }
        self.init(string: string)
    }
}
