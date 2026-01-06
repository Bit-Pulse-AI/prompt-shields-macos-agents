import Foundation
import CryptoKit
import os

// MARK: - Encryption Errors

/// Errors that can occur during string encryption/decryption operations
enum StringEncryptionError: Error, LocalizedError {
    case failedEncodingStringToData
    case failedBase64Encoding
    case failedBase64Decoding
    case decryptionFailed
    case encryptionKeyNotAvailable
    case invalidCiphertext

    var errorDescription: String? {
        switch self {
        case .failedEncodingStringToData:
            return "Failed to encode string to data"
        case .failedBase64Encoding:
            return "Failed to encode data to base64"
        case .failedBase64Decoding:
            return "Failed to decode base64 string"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .encryptionKeyNotAvailable:
            return "Encryption key is not available"
        case .invalidCiphertext:
            return "Invalid ciphertext format"
        }
    }
}

// MARK: - Secure String Operations

/// Thread-safe encryption key cache to avoid repeated keychain access
private actor EncryptionKeyCache {
    private var cachedKey: SymmetricKey?
    private let keychainManager: KeychainManager

    init(keychainManager: KeychainManager = KeychainManagerImpl.shared) {
        self.keychainManager = keychainManager
    }

    func getKey() throws -> SymmetricKey {
        if let key = cachedKey {
            return key
        }

        let key = try keychainManager.loadEncryptionKey()
        cachedKey = key
        return key
    }

    func invalidate() {
        cachedKey = nil
    }
}

/// Singleton cache for encryption key
private let keyCache = EncryptionKeyCache()

// MARK: - Secure String Extension

extension String {
    // MARK: - Secure Encryption

    /// Encrypts the string using AES-GCM with the stored encryption key
    /// Returns the original string if encryption fails (fail-safe for data integrity)
    var encrypt: String {
        do {
            return try encryptSecurely()
        } catch {
            // Log error but don't crash - return original for data integrity
            let logger = Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
                category: "SecureString"
            )
            logger.debug("Encryption failed: \(error.localizedDescription)")

            #if DEBUG
            // In debug, we want to know about encryption failures
            assertionFailure("Encryption failed: \(error)")
            #endif

            // Return base64 encoded original as fallback (not secure but preserves data)
            return Data(self.utf8).base64EncodedString()
        }
    }

    /// Decrypts the string using AES-GCM with the stored encryption key
    /// Returns an empty string if decryption fails (fail-safe)
    var decrypt: String {
        do {
            return try decryptSecurely()
        } catch {
            let logger = Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
                category: "SecureString"
            )
            logger.debug("Decryption failed: \(error.localizedDescription)")

            #if DEBUG
            assertionFailure("Decryption failed: \(error)")
            #endif

            // Try to decode as base64 fallback
            if let data = Data(base64Encoded: self),
               let decoded = String(data: data, encoding: .utf8) {
                return decoded
            }

            return ""
        }
    }

    // MARK: - Throwing Variants

    /// Encrypts the string, throwing on failure
    /// - Returns: The encrypted string
    /// - Throws: StringEncryptionError if encryption fails
    func encryptSecurely() throws -> String {
        // Use synchronous key retrieval for property wrapper compatibility
        let key = try KeychainManagerImpl.shared.loadEncryptionKey()
        return try encryptString(using: key)
    }

    /// Decrypts the string, throwing on failure
    /// - Returns: The decrypted string
    /// - Throws: StringEncryptionError if decryption fails
    func decryptSecurely() throws -> String {
        let key = try KeychainManagerImpl.shared.loadEncryptionKey()
        guard let decrypted = decryptString(using: key) else {
            throw StringEncryptionError.decryptionFailed
        }
        return decrypted
    }

    // MARK: - Core Encryption Methods

    /// Encrypts the string using the provided symmetric key
    /// - Parameter key: The symmetric key to use for encryption
    /// - Returns: Base64 encoded encrypted string
    /// - Throws: StringEncryptionError if encryption fails
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

    /// Decrypts the string using the provided symmetric key
    /// - Parameter key: The symmetric key to use for decryption
    /// - Returns: The decrypted string, or nil if decryption fails
    func decryptString(using key: SymmetricKey) -> String? {
        guard let combinedData = Data(base64Encoded: self) else {
            return nil
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - Optional String Extension

extension Optional where Wrapped == String {
    /// Encrypts the optional string
    var encrypt: String? {
        self?.encrypt
    }

    /// Decrypts the optional string
    var decrypt: String? {
        self?.decrypt
    }
}
