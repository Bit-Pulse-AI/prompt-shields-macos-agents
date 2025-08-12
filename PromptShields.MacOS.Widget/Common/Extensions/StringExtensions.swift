import Foundation

enum StringEncryptionError: Error {
    case failedEncodingStringToData
    case failedBase64Encoding
}
