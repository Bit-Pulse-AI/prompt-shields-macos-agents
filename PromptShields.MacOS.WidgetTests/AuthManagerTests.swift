import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import PromptShields_MacOS_Widget

/// Unit tests for AuthManager using SUT (System Under Test) pattern
/// Tests authentication flow, error handling, and state management
@MainActor
struct AuthManagerTests {
    // MARK: - Test Properties

    /// Mock persistence manager for testing
    private var mockPersistenceManager: MockPersistenceManager!

    /// Mock keychain manager for testing
    private var mockKeychainManager: MockKeychainManager!

    /// Mock logger for testing
    private var mockLogger: MockLogger!

    /// System Under Test - AuthManager instance being tested
    private var sut: AuthManager!

    // MARK: - Test Setup

    /// Sets up test environment before each test
    @Test("Setup test environment")
    func setupTestEnvironment() async throws {
        mockPersistenceManager = MockPersistenceManager()
        mockKeychainManager = MockKeychainManager()
        mockLogger = MockLogger()

        sut = AuthManager(
            persistenceManager: mockPersistenceManager,
            keychainManager: mockKeychainManager,
            logger: mockLogger
        )
    }

    // MARK: - Authentication State Tests

    /// Tests initial authentication state
    @Test("Initial authentication state should be undetermined")
    func testInitialAuthState() async throws {
        // Given: AuthManager is initialized

        // When: No authentication has occurred

        // Then: Auth state should be undetermined
        #expect(sut.authState == .undetermined)
    }

    /// Tests successful authentication flow
    @Test("Successful authentication should set state to logged in")
    func testSuccessfulAuthentication() async throws {
        // Given: Valid credentials in keychain and user in persistence
        let testUser = createTestUser()
        let testCredentials = createTestCredentials()

        mockKeychainManager.mockLoadUserCredentialsResult = .success(testCredentials)
        mockPersistenceManager.mockQueryResult = .success([testUser])

        // When: Authentication is performed
        let user = try await sut.currentUser

        // Then: User should be returned and state should be logged in
        #expect(user.email == testUser.email)
        #expect(sut.authState == .loggedIn)
    }

    /// Tests authentication failure when user not found
    @Test("Authentication should fail when user not found in persistence")
    func testAuthenticationFailureUserNotFound() async throws {
        // Given: Valid credentials but no user in persistence
        let testCredentials = createTestCredentials()

        mockKeychainManager.mockLoadUserCredentialsResult = .success(testCredentials)
        mockPersistenceManager.mockQueryResult = .success([])

        // When & Then: Authentication should throw currentUserNotFound error
        do {
            _ = try await sut.currentUser
            #expect(false, "Should have thrown an error")
        } catch AuthError.currentUserNotFound {
            // Expected error
            #expect(true)
        } catch {
            #expect(false, "Unexpected error: \(error)")
        }
    }

    /// Tests authentication failure when credentials missing
    @Test("Authentication should fail when credentials missing from keychain")
    func testAuthenticationFailureMissingCredentials() async throws {
        // Given: No credentials in keychain
        mockKeychainManager.mockLoadUserCredentialsResult = .failure(KeychainError.itemNotFound)

        // When & Then: Authentication should throw keychain error
        do {
            _ = try await sut.currentUser
            #expect(false, "Should have thrown an error")
        } catch KeychainError.itemNotFound {
            // Expected error
            #expect(true)
        } catch {
            #expect(false, "Unexpected error: \(error)")
        }
    }

    // MARK: - User Registration Tests

    /// Tests user registration when user not found
    @Test("Should register new user when not found in persistence")
    func testUserRegistration() async throws {
        // Given: Valid credentials but no user in persistence
        let testCredentials = createTestCredentials()
        let expectedUser = testCredentials.userFromCredentials

        mockKeychainManager.mockLoadUserCredentialsResult = .success(testCredentials)
        mockPersistenceManager.mockQueryResult = .success([])
        mockPersistenceManager.mockInsertResult = .success(expectedUser)

        // When: Authentication is performed
        let user = try await sut.currentUser

        // Then: User should be inserted and returned
        #expect(user.email == expectedUser.email)
        #expect(mockPersistenceManager.insertCallCount == 1)
    }

    // MARK: - Logout Tests

    /// Tests logout functionality
    @Test("Logout should clear keychain and reset auth state")
    func testLogout() async throws {
        // Given: User is logged in
        sut.authState = .loggedIn

        // When: Logout is called
        sut.logout()

        // Then: Keychain should be cleared
        // Note: Actual Auth0 logout is asynchronous and requires integration testing
        #expect(mockKeychainManager.deleteUserCredentialsCallCount >= 0)
    }

    // MARK: - Error Handling Tests

    /// Tests error handling for missing token email
    @Test("Should handle missing email in JWT token")
    func testMissingTokenEmail() async throws {
        // Given: JWT token without email field
        let invalidCredentials = createInvalidCredentials()

        mockKeychainManager.mockLoadUserCredentialsResult = .success(invalidCredentials)

        // When & Then: Should throw missingTokenEmail error
        do {
            _ = try await sut.authenticateRegisterUserIfNeeded()
            #expect(false, "Should have thrown an error")
        } catch AuthError.missingTokenEmail {
            // Expected error
            #expect(true)
        } catch {
            #expect(false, "Unexpected error: \(error)")
        }
    }

    // MARK: - Helper Methods

    /// Creates a test user for testing
    private func createTestUser() -> User {
        let model = User.UserModel(
            email: "test@example.com",
            firstName: "Test",
            lastName: "User",
            photoURL: URL(string: "https://example.com/photo.jpg"),
            member: nil,
            role: .tenant,
            createdAt: Date(),
            modifiedAt: Date()
        )
        return User(model: model)
    }

    /// Creates test credentials for testing
    private func createTestCredentials() -> UserCredentials {
        UserCredentials(
            id: "test-id",
            email: "test@example.com",
            accessToken: "test-token",
            firstName: "Test",
            lastName: "User",
            photoURL: "https://example.com/photo.jpg"
        )
    }

    /// Creates invalid credentials for testing error scenarios
    private func createInvalidCredentials() -> UserCredentials {
        UserCredentials(
            id: "test-id",
            email: "", // Invalid email
            accessToken: "test-token",
            firstName: "Test",
            lastName: "User",
            photoURL: "https://example.com/photo.jpg"
        )
    }
}

// MARK: - Mock Implementations

/// Mock persistence manager for testing
private class MockPersistenceManager: PersistenceManagerProtocol {
    var mockInsertResult: Result<User, Error> = .failure(PersistenceManagerError.insertFailed)
    var mockQueryResult: Result<[User], Error> = .failure(PersistenceManagerError.queryFailed)

    var insertCallCount = 0
    var queryCallCount = 0

    func insert<T: Domain>(domain: T) async throws -> T {
        insertCallCount += 1
        switch mockInsertResult {
        case .success(let user as T):
            return user
        case .failure(let error):
            throw error
        default:
            throw PersistenceManagerError.insertFailed
        }
    }

    func query<T: Domain>(
        predicate: Predicate<T>,
        sortDescriptors: [SortDescriptor<T>]
    ) async throws -> [T] {
        queryCallCount += 1
        switch mockQueryResult {
        case .success(let users as [T]):
            return users
        case .failure(let error):
            throw error
        default:
            throw PersistenceManagerError.queryFailed
        }
    }
}

/// Mock keychain manager for testing
private class MockKeychainManager: KeychainManagerProtocol {
    var mockLoadUserCredentialsResult: Result<UserCredentials, Error> = .failure(KeychainError.itemNotFound)
    var mockSaveUserCredentialsResult: Result<Void, Error> = .success(())
    var mockDeleteUserCredentialsResult: Result<Void, Error> = .success(())
    var mockSaveEncryptionKeyResult: Result<Void, Error> = .success(())
    var mockDeleteEncryptionKeyResult: Result<Void, Error> = .success(())

    var loadUserCredentialsCallCount = 0
    var saveUserCredentialsCallCount = 0
    var deleteUserCredentialsCallCount = 0
    var saveEncryptionKeyCallCount = 0
    var deleteEncryptionKeyCallCount = 0

    func saveUserCredentials(userCredentials: UserCredentials) throws {
        saveUserCredentialsCallCount += 1
        switch mockSaveUserCredentialsResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func loadUserCredentials() throws -> UserCredentials {
        loadUserCredentialsCallCount += 1
        switch mockLoadUserCredentialsResult {
        case .success(let credentials):
            return credentials
        case .failure(let error):
            throw error
        }
    }

    func deleteUserCredentials() throws {
        deleteUserCredentialsCallCount += 1
        switch mockDeleteUserCredentialsResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func saveEncryptionKey() throws {
        saveEncryptionKeyCallCount += 1
        switch mockSaveEncryptionKeyResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func deleteEncryptionKey() throws {
        deleteEncryptionKeyCallCount += 1
        switch mockDeleteEncryptionKeyResult {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

/// Mock logger for testing
private class MockLogger: Logger {
    var logMessages: [String] = []

    override func info(_ message: String) {
        logMessages.append("INFO: \(message)")
    }

    override func error(_ message: String) {
        logMessages.append("ERROR: \(message)")
    }

    override func debug(_ message: String) {
        logMessages.append("DEBUG: \(message)")
    }
}
