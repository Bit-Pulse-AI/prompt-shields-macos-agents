import XCTest
import SwiftData
@testable import PromptShields_MacOS_Widget

/// Tests for pagination functionality in ChannelDomainService
final class PaginationTests: XCTestCase {
    // MARK: - Test Properties
    
    private var mockChannelNetworkService: MockChannelNetworkService!
    private var mockLLMNetworkService: MockLLMNetworkService!
    private var mockKeychainManager: MockKeychainManager!
    private var mockPersistenceManager: MockPersistenceManager!
    private var channelDomainService: ChannelDomainServiceImpl<MockKeychainManager, MockPersistenceManager>!
    
    // MARK: - Setup and Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockChannelNetworkService = MockChannelNetworkService()
        mockLLMNetworkService = MockLLMNetworkService()
        mockKeychainManager = MockKeychainManager()
        mockPersistenceManager = MockPersistenceManager()
        
        channelDomainService = ChannelDomainServiceImpl(
            channelNetworkService: mockChannelNetworkService,
            llmNetworkService: mockLLMNetworkService,
            keychainManager: mockKeychainManager,
            persistenceManager: mockPersistenceManager
        )
    }
    
    override func tearDown() async throws {
        mockChannelNetworkService = nil
        mockLLMNetworkService = nil
        mockKeychainManager = nil
        mockPersistenceManager = nil
        channelDomainService = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Pagination Tests
    
    /// Tests that pagination correctly fetches multiple pages of channels
    func testPaginationFetchesMultiplePages() async throws {
        // Given: Mock projects and paginated responses
        let mockProjects = [
            Project(model: .init(uuid: "project1", name: "Project 1", description: "", createdAt: Date(), modifiedAt: Date())),
            Project(model: .init(uuid: "project2", name: "Project 2", description: "", createdAt: Date(), modifiedAt: Date()))
        ]
        
        let mockChannelDTOs = [
            ChannelDTO(id: "channel1", title: "Channel 1", status: .active, createdAt: Date(), updatedAt: Date()),
            ChannelDTO(id: "channel2", title: "Channel 2", status: .active, createdAt: Date(), updatedAt: Date())
        ]
        
        let paginatedResponse = PaginatedResponse<ChannelDTO>(
            items: mockChannelDTOs,
            total: 4,
            offset: 1,
            limit: 2,
            hasNext: true,
            hasPrevious: false
        )
        
        // Setup mocks
        mockPersistenceManager.mockProjects = mockProjects
        mockChannelNetworkService.mockPaginatedResponse = paginatedResponse
        
        // When: Fetching all channels with pagination
        var localDataCalled = false
        var remoteDataCalled = false
        var receivedResult: FetchDashboardResult?
        
        channelDomainService.fetchAll(
            localData: { _ in
                localDataCalled = true
            },
            remoteData: { result in
                remoteDataCalled = true
                receivedResult = result
            }
        )
        
        // Wait for async operations
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Then: Verify pagination was used
        XCTAssertTrue(localDataCalled, "Local data should be called")
        XCTAssertTrue(remoteDataCalled, "Remote data should be called")
        XCTAssertNotNil(receivedResult, "Should receive a result")
        
        // Verify network service was called with pagination parameters
        XCTAssertTrue(mockChannelNetworkService.listCalled, "List method should be called")
        XCTAssertEqual(mockChannelNetworkService.lastPage, 1, "Should start with page 1")
        XCTAssertEqual(mockChannelNetworkService.lastPageSize, 20, "Should use default page size")
    }
    
    /// Tests that pagination handles empty responses correctly
    func testPaginationHandlesEmptyResponse() async throws {
        // Given: Empty paginated response
        let emptyResponse = PaginatedResponse<ChannelDTO>(
            items: [],
            total: 0,
            offset: 1,
            limit: 20,
            hasNext: false,
            hasPrevious: false
        )
        
        mockPersistenceManager.mockProjects = []
        mockChannelNetworkService.mockPaginatedResponse = emptyResponse
        
        // When: Fetching all channels
        var remoteDataCalled = false
        var receivedResult: FetchDashboardResult?
        
        channelDomainService.fetchAll(
            localData: { _ in },
            remoteData: { result in
                remoteDataCalled = true
                receivedResult = result
            }
        )
        
        // Wait for async operations
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Then: Verify empty response is handled
        XCTAssertTrue(remoteDataCalled, "Remote data should be called")
        XCTAssertNotNil(receivedResult, "Should receive a result")
        XCTAssertEqual(receivedResult?.allChannels.count, 0, "Should have no channels")
    }
    
    /// Tests that pagination respects the hasNext flag
    func testPaginationRespectsHasNextFlag() async throws {
        // Given: Response with hasNext = false
        let mockChannelDTOs = [
            ChannelDTO(id: "channel1", title: "Channel 1", status: .active, createdAt: Date(), updatedAt: Date())
        ]
        
        let paginatedResponse = PaginatedResponse<ChannelDTO>(
            items: mockChannelDTOs,
            total: 1,
            page: 1,
            pageSize: 20,
            hasNext: false,
            hasPrevious: false
        )
        
        let mockProjects = [
            Project(model: .init(uuid: "project1", name: "Project 1", description: "", createdAt: Date(), modifiedAt: Date()))
        ]
        
        mockPersistenceManager.mockProjects = mockProjects
        mockChannelNetworkService.mockPaginatedResponse = paginatedResponse
        
        // When: Fetching all channels
        var remoteDataCalled = false
        
        channelDomainService.fetchAll(
            localData: { _ in },
            remoteData: { _ in
                remoteDataCalled = true
            }
        )
        
        // Wait for async operations
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Then: Verify only one page is fetched when hasNext is false
        XCTAssertTrue(remoteDataCalled, "Remote data should be called")
        XCTAssertEqual(mockChannelNetworkService.listCallCount, 1, "Should only call list once when hasNext is false")
    }
}

// MARK: - Mock Implementations

private class MockChannelNetworkService: ChannelNetworkService {
    var networkManager: NetworkManager = MockNetworkManager()
    
    var listCalled = false
    var lastPage: Int = 0
    var lastPageSize: Int = 0
    var listCallCount = 0
    var mockPaginatedResponse: PaginatedResponse<ChannelDTO>?
    
    func list(projectId: String, page: Int, pageSize: Int) async throws -> PaginatedResponse<ChannelDTO> {
        listCalled = true
        lastPage = page
        lastPageSize = pageSize
        listCallCount += 1
        
        guard let response = mockPaginatedResponse else {
            throw NetworkError(message: "No mock response configured")
        }
        
        return response
    }
    
    func delete(projectId: String, channelId: String) async throws {}
    func create(projectId: String, title: String) async throws -> ChannelDTO {
        throw NetworkError(message: "Not implemented")
    }
    func update(projectId: String, channelId: String, title: String?) async throws -> ChannelDTO {
        throw NetworkError(message: "Not implemented")
    }
    func update(projectId: String, channelId: String, title: String?, channelStatus: ChannelStatus?, memberIds: [String]?) async throws -> ChannelDTO {
        throw NetworkError(message: "Not implemented")
    }
}

private class MockLLMNetworkService: LLMNetworkService {
    var networkManager: NetworkManager = MockNetworkManager()
    
    func redact(message: String) async throws -> RedactionResponse {
        throw NetworkError(message: "Not implemented")
    }
    
    func chat(message: String, llmProvider: String) async throws -> MessageResponse {
        throw NetworkError(message: "Not implemented")
    }
    
    func getLLMs() async throws -> LLMsResponse {
        throw NetworkError(message: "Not implemented")
    }
    
    func getAvailableModels() async throws -> [LLMInfoResponse] {
        throw NetworkError(message: "Not implemented")
    }
}

private class MockKeychainManager: KeychainManager {
    func saveUserCredentials(userCredentials: UserCredentials) throws {}
    func loadUserCredentials() throws -> UserCredentials {
        throw KeychainError.loadFailed
    }
    func deleteUserCredentials() throws {}
    func saveEncryptionKey() throws {}
    func deleteEncryptionKey() async throws {}
}

private class MockPersistenceManager: PersistenceManager {
    var mockProjects: [Project] = []
    
    func query<D>() async throws -> [D] where D: Domain, D.M == D.S.D.M {
        if D.self == Project.self {
            return mockProjects as! [D]
        }
        return []
    }
    
    func query<D>(sortDescriptors: [SortDescriptor<D.S>]) async throws -> [D] where D: Domain, D.M == D.S.D.M {
        if D.self == Project.self {
            return mockProjects as! [D]
        }
        return []
    }
    
    func query<D>(predicate: Predicate<D.S>?) async throws -> [D] where D.S.D.M == D.M {
        return []
    }
    
    func query<D>(predicate: Predicate<D.S>?, sortDescriptors: [SortDescriptor<D.S>]) async throws -> [D] where D.S.D.M == D.M {
        return []
    }
    
    func insert<D>(domain: D) async throws -> D where D.S.D == D {
        return domain
    }
    
    func update<D>(domain: D) async throws where D.S.D == D {}
    func update<D>(domains: [D]) async throws where D.S.D == D {}
    func fetchItem<D>(persistentIdentifier: PersistentIdentifier) async throws -> D where D.S.D == D {
        throw PersistenceManagerError.modelNotFound
    }
    func fetchItem<D>(persistentIdentifier: PersistentIdentifier?) async throws -> D where D.S.D == D {
        throw PersistenceManagerError.modelNotFound
    }
    func fetchItem<D>(uid: UID) async throws -> D where D.S.D == D {
        throw PersistenceManagerError.modelNotFound
    }
    func delete<D>(domain: D) async throws {}
    func logout() async throws {}
}

private class MockNetworkManager: NetworkManager {
    func perform(request: URLRequest) async throws -> Data {
        return Data()
    }
} 
