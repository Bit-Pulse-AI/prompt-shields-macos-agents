import Foundation
import CryptoKit

// MARK: - Mapping Error

enum MappingError: Error, LocalizedError {
    case mappingURLError

    var errorDescription: String? {
        switch self {
        case .mappingURLError:
            return "Failed to convert string to URL"
        }
    }
}
// MARK: - Encrypt Result

struct EncryptResult: Sendable {
    let ephemeralPubKeyPem: String
    let encryptedSecret: Data
    let nonce: AES.GCM.Nonce
}

// MARK: - String Extension

extension String {
    // MARK: - Asymmetric Encryption (P-521 ECDH)

    /// Encrypts the string using P-521 ECDH key agreement
    /// - Parameters:
    ///   - publicKey: The recipient's public key in PEM format
    ///   - info: Additional info for key derivation
    /// - Returns: The encryption result containing ephemeral public key, ciphertext, and nonce
    func encrypt(publicKey: String, info: String) async throws -> EncryptResult? {
        let key = try P521.KeyAgreement.PublicKey(pemRepresentation: publicKey)

        let ephemeralPrivKey = P521.KeyAgreement.PrivateKey()
        let ephemeralPubKey = ephemeralPrivKey.publicKey

        // Perform ECDH key agreement
        let sharedSecret = try ephemeralPrivKey.sharedSecretFromKeyAgreement(with: key)

        // Derive symmetric AES key from shared secret
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(info.utf8),
            outputByteCount: 32
        )

        // Encrypt secret using AES-GCM
        guard let secretData = data(using: .utf8) else {
            return nil
        }

        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(secretData, using: symmetricKey, nonce: nonce)

        // Export ephemeral public key as PEM string
        let ephemeralPubKeyPem = ephemeralPubKey.pemRepresentation

        return EncryptResult(
            ephemeralPubKeyPem: ephemeralPubKeyPem,
            encryptedSecret: sealedBox.ciphertext + sealedBox.tag,
            nonce: nonce
        )
    }

    static func stringFromBundleFile(
        named name: String,
        extension ext: String = "txt",
        encoding: String.Encoding = .utf8
    ) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            return "n/a"
        }
        return (try? String(contentsOf: url, encoding: encoding)) ?? "n/a"
    }

    // MARK: - URL Conversion

    /// Converts the string to a URL
    /// - Throws: MappingError.mappingURLError if conversion fails
    var url: URL {
        get throws {
            guard let url = URL(string: self) else {
                throw MappingError.mappingURLError
            }
            return url
        }
    }

    /// Decrypts the string and converts to URL
    var decryptedURL: URL {
        get throws {
            try decrypt.url
        }
    }

    // MARK: - Base64 Encoding

    /// Converts the string to base64
    func toBase64() -> String {
        Data(self.utf8).base64EncodedString()
    }

    /// Creates a string from base64 encoded data
    static func fromBase64(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded
    }

    // MARK: - Hashing

    /// Returns the SHA-512 hash of the string
    var sha512: String {
        get throws {
            guard let data = data(using: .utf8) else {
                throw StringErrors.invalidStringToData
            }
            let digest = SHA512.hash(data: data)
            return digest
                .compactMap { String(format: "%02x", $0) }
                .joined()
        }
    }

    // MARK: - String Replacement

    /// Replaces multiple substrings at specified positions
    /// - Parameter replacements: Array of replacements to apply
    /// - Returns: The string with all replacements applied
    func replaceMultiple(_ replacements: [StringReplacement]) -> String {
        let sortedReplacements = replacements.sorted { $0.startPosition < $1.startPosition }

        var result = self
        var offset = 0

        for replacement in sortedReplacements {
            let adjustedStart = replacement.startPosition + offset
            let adjustedEnd = replacement.endPosition + offset

            guard adjustedStart >= 0 && adjustedEnd <= result.count && adjustedStart <= adjustedEnd else {
                continue
            }

            let startIndex = result.index(result.startIndex, offsetBy: adjustedStart)
            let endIndex = result.index(result.startIndex, offsetBy: adjustedEnd)
            let range = startIndex..<endIndex

            let originalLength = result.distance(from: startIndex, to: endIndex)
            let newLength = replacement.replacementText.count
            let lengthDifference = newLength - originalLength

            result.replaceSubrange(range, with: replacement.replacementText)

            offset += lengthDifference
        }

        return result
    }

    /// Optimized version of replaceMultiple using NSString
    /// - Parameter replacements: Array of replacements to apply
    /// - Returns: The string with all replacements applied
    func replaceMultipleOptimized(_ replacements: [StringReplacement]) -> String {
        // Sort replacements by start position (descending to avoid position shifts)
        let sortedReplacements = replacements.sorted { $0.startPosition > $1.startPosition }

        var result = self

        for replacement in sortedReplacements {
            // Validate positions
            guard replacement.startPosition >= 0 &&
                  replacement.endPosition <= result.count &&
                  replacement.startPosition <= replacement.endPosition else {
                continue
            }

            // Create NSRange for the replacement
            let range = NSRange(
                location: replacement.startPosition,
                length: replacement.endPosition - replacement.startPosition
            )

            // Perform replacement using NSString
            let nsString = result as NSString
            result = nsString.replacingCharacters(in: range, with: replacement.replacementText)
        }

        return result
    }
}

// MARK: - String Replacement

/// Represents a text replacement operation
struct StringReplacement: Sendable {
    let replacementText: String
    let startPosition: Int
    let endPosition: Int
}
