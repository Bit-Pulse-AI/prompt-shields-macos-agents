import Security
import CommonCrypto
import CryptoKit
import Foundation

enum KeychainManagerKey: String {
    case userCredentials
    case encryptionToken
}
enum KeychainManagerErrors: Error {
    case missingCredentialData
}

/// Protocol for keychain operations to enable testing
protocol KeychainManager: Sendable {
    var applicationJSONAuthorizedHeader: [String: String] { get throws }
    /// Saves user credentials to keychain
    /// - Parameter userCredentials: User credentials to save
    /// - Throws: Keychain errors if save operation fails
    func saveUserCredentials(userCredentials: UserAPIResponse) throws
    
    /// Loads user credentials from keychain
    /// - Returns: User credentials if found
    /// - Throws: Keychain errors if load operation fails
    @discardableResult
    func loadUserCredentials() throws -> UserAPIResponse
    
    /// Deletes user credentials from keychain
    /// - Throws: Keychain errors if delete operation fails
    func deleteUserCredentials() throws
    
    /// Saves encryption key to keychain
    /// - Throws: Keychain errors if save operation fails
    func saveEncryptionKey() throws
    
    /// Deletes encryption key from keychain
    /// - Throws: Keychain errors if delete operation fails
    func deleteEncryptionKey() throws
    
    func loadEncryptionKey() throws -> SymmetricKey
}

struct KeychainManagerImpl: KeychainManager {
    private let service: String = "ai.promptshields.widget.service"
    static let shared = KeychainManagerImpl()
    
    var applicationJSONAuthorizedHeader: [String: String] {
        get throws {
            var authorizationHeader = try authorizationHeader
            authorizationHeader.updateValue("application/json", forKey: "Content-Type")
            authorizationHeader.updateValue("application/json", forKey: "Accept")
            return authorizationHeader
        }
    }
    var authorizationHeader: [String: String] {
        get throws {
            let accessToken = try loadUserCredentials().accessToken
            return ["Authorization": "Bearer \(accessToken)"]
        }
    }
    
    @discardableResult
    func loadUserCredentials() throws -> UserAPIResponse {
        let data = try loadSecureData(key: .userCredentials)
        return try JSONDecoder()
            .decode(UserAPIResponse.self,
                    from: data)
    }
    
    func loadEncryptionKey() throws -> SymmetricKey {
        let data = try loadSecureData(key: .encryptionToken)
        return SymmetricKey(data: data)
    }
    
    func deleteUserCredentials() throws {
        try deleteSecureData(key: .userCredentials)
    }
    
    func deleteEncryptionKey() throws {
        try deleteSecureData(key: .encryptionToken)
    }
    
    func saveUserCredentials(userCredentials: UserAPIResponse) throws {
        try saveUserCredentials(userCredentials: userCredentials, override: true)
    }
    
    func saveUserCredentials(userCredentials: UserAPIResponse, override: Bool = true) throws {
        let data = try JSONEncoder().encode(userCredentials)
        try saveSecureData(key: .userCredentials, secureData: data, override: override)
    }
    
    func saveEncryptionKey() throws {
        let key = SymmetricKey(size: .bits256)
        return try saveSecureData(key: .encryptionToken,
                                  secureData: key.withUnsafeBytes { Data($0) },
                                  override: true)
    }
    
    // Private

    private func saveSecureData(key: KeychainManagerKey,
                                       secureData: Data,
                                       override: Bool) throws {
        let serviceHashed = try service.sha512
        let accountHashed = try key.rawValue.sha512
        let query = [
            kSecValueData: secureData,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceHashed,
            kSecAttrAccount: accountHashed
        ] as CFDictionary
                    
        let saveStatus = SecItemAdd(query, nil)
            
        if saveStatus != errSecSuccess {
            if override && saveStatus == -25299 {
                let searchQuery = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrService: serviceHashed,
                    kSecAttrAccount: accountHashed
                ] as CFDictionary
                SecItemUpdate(searchQuery, query)
            } else {
                throw KeychainError.savingError
            }
        }
    }
    
    private func deleteSecureData(key: KeychainManagerKey) throws {
        let serviceHashed = try service.sha512
        let accountHashed = try key.rawValue.sha512
        let query = [
          kSecClass: kSecClassGenericPassword,
          kSecAttrService: serviceHashed,
          kSecAttrAccount: accountHashed
        ] as CFDictionary

        if SecItemDelete(query) != errSecSuccess {
            throw KeychainError.deleteError
        }
    }
    
    private func loadSecureData(key: KeychainManagerKey) throws -> Data {
        let serviceHashed = try service.sha512
        let accountHashed = try key.rawValue.sha512
          let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceHashed,
            kSecAttrAccount: accountHashed,
            kSecReturnData: true
          ] as CFDictionary

        var result: AnyObject?
        SecItemCopyMatching(query, &result)
        guard let result = result as? Data else {
            throw KeychainError.loadError
        }
        return result
    }
}
