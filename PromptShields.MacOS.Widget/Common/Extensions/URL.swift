import Foundation

extension URL {
    var encrypt: String {
        absoluteString.encrypt
    }
    
    init?(string: String?) {
        guard let string else {
             return nil
        }
        self.init(string: string)
    }
}
