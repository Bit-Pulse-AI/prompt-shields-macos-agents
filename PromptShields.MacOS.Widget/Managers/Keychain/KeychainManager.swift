import Security
import CommonCrypto
import CryptoKit
import Foundation
import os

// MARK: - Keychain Manager Key

/// Keys used for storing data in the keychain
enum KeychainManagerKey: String, Sendable {
    case userCredentials
    case encryptionToken
}

// MARK: - Keychain Manager Errors

/// Errors that can occur during keychain operations
enum KeychainManagerErrors: Error, LocalizedError {
    case missingCredentialData

    var errorDescription: String? {
        switch self {
        case .missingCredentialData:
            return "Required credential data is missing"
        }
    }
}

// MARK: - Keychain Error

/// Detailed keychain operation errors
enum KeychainError: Error, LocalizedError {
    case savingError
    case loadError
    case deleteError
    case dataEncodingError
    case dataDecodingError
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .savingError:
            return "Failed to save item to keychain"
        case .loadError:
            return "Failed to load item from keychain"
        case .deleteError:
            return "Failed to delete item from keychain"
        case .dataEncodingError:
            return "Failed to encode data for keychain storage"
        case .dataDecodingError:
            return "Failed to decode data from keychain"
        case .itemNotFound:
            return "Item not found in keychain"
        case .duplicateItem:
            return "Item already exists in keychain"
        case .unexpectedStatus(let status):
            return "Unexpected keychain error: \(status)"
        }
    }
}

// MARK: - Keychain Manager Protocol

/// Protocol for keychain operations
/// Follows Interface Segregation Principle - focused on credential management
protocol KeychainManager: Sendable {
    /// Returns authorization headers for API requests
    var applicationJSONAuthorizedHeader: [String: String] { get throws }

    /// Returns just the authorization header
    var authorizationHeader: [String: String] { get throws }

    /// Saves user credentials to keychain
    /// - Parameter userCredentials: User credentials to save
    /// - Throws: KeychainError if save operation fails
    func saveUserCredentials(userCredentials: UserAPIResponse) throws

    /// Loads user credentials from keychain
    /// - Returns: User credentials if found
    /// - Throws: KeychainError if load operation fails
    @discardableResult
    func loadUserCredentials() throws -> UserAPIResponse

    /// Deletes user credentials from keychain
    /// - Throws: KeychainError if delete operation fails
    func deleteUserCredentials() throws

    /// Saves a new encryption key to keychain
    /// - Throws: KeychainError if save operation fails
    func saveEncryptionKey() throws

    /// Deletes encryption key from keychain
    /// - Throws: KeychainError if delete operation fails
    func deleteEncryptionKey() throws

    /// Loads the encryption key from keychain
    /// - Returns: The symmetric encryption key
    /// - Throws: KeychainError if load operation fails
    func loadEncryptionKey() throws -> SymmetricKey
}

// MARK: - Keychain Manager Implementation

/// Thread-safe keychain manager implementation
struct KeychainManagerImpl: KeychainManager, @unchecked Sendable {
    // MARK: - Properties

    /// Service identifier for keychain items
    private let service: String

    /// Access group for keychain sharing (optional)
    private let accessGroup: String?

    /// Logger for keychain operations
    private let logger: Logger

    // MARK: - Singleton

    static let shared = KeychainManagerImpl()

    // MARK: - Initialization

    init(
        service: String = "ai.promptshields.widget.service",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
            category: "KeychainManager"
        )
    }

    // MARK: - Headers

    var applicationJSONAuthorizedHeader: [String: String] {
        get throws {
            var headers = try authorizationHeader
            headers["Content-Type"] = "application/json"
            headers["Accept"] = "application/json"
            return headers
        }
    }

    var authorizationHeader: [String: String] {
        get throws {
            let accessToken = try loadUserCredentials().accessToken
            return ["Authorization": "Bearer \(accessToken)"]
        }
    }

    // MARK: - User Credentials

    @discardableResult
    func loadUserCredentials() throws -> UserAPIResponse {
        let data = try loadSecureData(key: .userCredentials)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(UserAPIResponse.self, from: data)
        } catch {
            logger.error("Failed to decode user credentials: \(error.localizedDescription)")
            throw KeychainError.dataDecodingError
        }
    }

    func saveUserCredentials(userCredentials: UserAPIResponse) throws {
        try saveUserCredentials(userCredentials: userCredentials, override: true)
    }

    func saveUserCredentials(userCredentials: UserAPIResponse, override: Bool) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(userCredentials)
            try saveSecureData(key: .userCredentials, secureData: data, override: override)
        } catch let error as KeychainError {
            throw error
        } catch {
            logger.error("Failed to encode user credentials: \(error.localizedDescription)")
            throw KeychainError.dataEncodingError
        }
    }

    func deleteUserCredentials() throws {
        try deleteSecureData(key: .userCredentials)
    }

    // MARK: - Encryption Key

    func loadEncryptionKey() throws -> SymmetricKey {
        let data = try loadSecureData(key: .encryptionToken)
        return SymmetricKey(data: data)
    }

    func saveEncryptionKey() throws {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try saveSecureData(key: .encryptionToken, secureData: keyData, override: true)
    }

    func deleteEncryptionKey() throws {
        try deleteSecureData(key: .encryptionToken)
    }

    // MARK: - Private Methods

    private func saveSecureData(key: KeychainManagerKey, secureData: Data, override: Bool) throws {
        let serviceHashed = try service.sha512
        let accountHashed = try key.rawValue.sha512

        var query: [CFString: Any] = [
            kSecValueData: secureData,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceHashed,
            kSecAttrAccount: accountHashed,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }

        let saveStatus = SecItemAdd(query as CFDictionary, nil)

        switch saveStatus {
        case errSecSuccess:
            logger.debug("Successfully saved keychain item: \(key.rawValue)")

        case errSecDuplicateItem where override:
            // Update existing item
            let searchQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: serviceHashed,
                kSecAttrAccount: accountHashed
            ]

            let updateQuery: [CFString: Any] = [
                kSecValueData: secureData
            ]

            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateQuery as CFDictionary)

            guard updateStatus == errSecSuccess else {
                logger.error("Failed to update keychain item: \(updateStatus)")
                throw KeychainError.unexpectedStatus(updateStatus)
            }

            logger.debug("Successfully updated keychain item: \(key.rawValue)")

        case errSecDuplicateItem:
            throw KeychainError.duplicateItem

        default:
            logger.error("Failed to save keychain item: \(saveStatus)")
            throw KeychainError.savingError
        }
    }

    private func deleteSecureData(key: KeychainManagerKey) throws {
        let serviceHashed = try service.sha512
        let accountHashed = try key.rawValue.sha512

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceHashed,
            kSecAttrAccount: accountHashed
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Failed to delete keychain item: \(status)")
            throw KeychainError.deleteError
        }

        logger.debug("Successfully deleted keychain item: \(key.rawValue)")
    }

    private func loadSecureData(key: KeychainManagerKey) throws -> Data {
        let serviceHashed = try service.sha512
        let accountHashed = try key.rawValue.sha512

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceHashed,
            kSecAttrAccount: accountHashed,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            logger.error("Failed to load keychain item: \(status)")
            throw KeychainError.loadError
        }

        guard let data = result as? Data else {
            throw KeychainError.dataDecodingError
        }

        return data
    }
}
