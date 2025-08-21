import Foundation
import CryptoKit

enum MappingError: Error {
    case mappingURLError
}

struct EncryptResult {
    let ephemeralPubKeyPem: String
    let encryptedSecret: Data
    let nonce: AES.GCM.Nonce
}

extension String {
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
        let secretData = data(using: .utf8)!
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(secretData, using: symmetricKey, nonce: nonce)
        
        // Export ephemeral public key as PEM string
        let ephemeralPubKeyPem = ephemeralPubKey.pemRepresentation
        
        return EncryptResult(ephemeralPubKeyPem: ephemeralPubKeyPem, encryptedSecret: sealedBox.ciphertext + sealedBox.tag, nonce: nonce)
    }
    
    var url: URL {
        get throws {
            guard let url = URL(string: self) else {
                throw MappingError.mappingURLError
            }
            return url
        }
    }
    var decryptedURL: URL {
        get throws {
            try decrypt.url
        }
    }
    
    func toBase64() -> String {
        return Data(self.utf8).base64EncodedString()
    }

    static func fromBase64(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded
    }
    
    var sha512: String {
        get throws {
            guard let data = data(using: .utf8) else {
                throw StringErrors.invalidStringToData
            }
            let digest = SHA512.hash(data: data)
            let hashString = digest
                .compactMap { String(format: "%02x", $0) }
                .joined()
            return hashString
        }
    }
    
    func encryptString(using key: SymmetricKey) throws -> String {
        guard let data = data(using: .utf8) else {
            throw StringEncryptionError.failedEncodingStringToData
        }
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let encryptedString = sealedBox.combined?.base64EncodedString() else {
            throw StringEncryptionError.failedBase64Encoding
        }
        return encryptedString
    }

    func decryptString(using key: SymmetricKey) -> String? {
        guard let combinedData = Data(base64Encoded: self) else { return nil }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    var encrypt: String {
        do {
            let key = try KeychainManagerImpl.shared.loadEncryptionKey()
            let encryptedString = try encryptString(using: key)
            
            return encryptedString
        } catch {
            fatalError("E100: Please contact technical support.")
        }
    }

    var decrypt: String {
        do {
            let key = try KeychainManagerImpl.shared.loadEncryptionKey()
            guard let decryptedString = decryptString(using: key) else {
                fatalError("E102: Please contact technical support.")
            }
            return decryptedString
        } catch {
            fatalError("E101: Please contact technical support.")
        }
    }
    
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
            let range = NSRange(location: replacement.startPosition,
                              length: replacement.endPosition - replacement.startPosition)
            
            // Perform replacement using NSString
            let nsString = result as NSString
            result = nsString.replacingCharacters(in: range, with: replacement.replacementText)
        }
        
        return result
    }
}

struct StringReplacement {
    let replacementText: String
    let startPosition: Int
    let endPosition: Int
}
