import XCTest
import SwiftData
@testable import PromptShields_MacOS_Widget

final class ProjectPaginationTests: XCTestCase {
    var mockProjectNetworkService: MockProjectNetworkService!
    var mockKeychainManager: MockKeychainManager!
    var mockPersistenceManager: MockPersistenceManager!
    var projectDomainService: ProjectDomainServiceImpl<MockKeychainManager, MockPersistenceManager, MockProjectNetworkService>!

    override func setUp() {
        super.setUp()
        mockProjectNetworkService = MockProjectNetworkService()
        mockKeychainManager = MockKeychainManager()
        mockPersistenceManager = MockPersistenceManager()
        projectDomainService = ProjectDomainServiceImpl(
            projectNetworkService: mockProjectNetworkService,
            keychainManager: mockKeychainManager,
            persistenceManager: mockPersistenceManager
        )
    }

    override func tearDown() {
        mockProjectNetworkService = nil
        mockKeychainManager = nil
        mockPersistenceManager = nil
        projectDomainService = nil
        super.tearDown()
    }

    // MARK: - Project Domain Service Tests

    func testFetchAll_WithMultiplePages_LoadsAllProjects() async throws {
        // Given
        let localProjects = createMockProjects(count: 5)
        mockPersistenceManager.mockProjects = localProjects

        let remoteProjects = createMockProjectDTOs(count: 15)
        let paginatedResponse = PaginatedResponse(
            items: remoteProjects,
            hasNext: true,
            totalItems: 20,
            currentPage: 1,
            pageSize: 10
        )
        mockProjectNetworkService.mockPaginatedResponse = paginatedResponse

        var localDataCalled = false
        var remoteDataCalled = false
        var receivedProjects: [Project] = []

        // When
        projectDomainService.fetchAll(
            localData: { projects in
                localDataCalled = true
                XCTAssertEqual(projects.count, 5)
            },
            remoteData: { projects in
                remoteDataCalled = true
                receivedProjects = projects
            }
        )

        // Wait for async operations
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Then
        XCTAssertTrue(localDataCalled, "Local data should be called first")
        XCTAssertTrue(remoteDataCalled, "Remote data should be called after sync")
        XCTAssertEqual(receivedProjects.count, 15, "Should receive all remote projects")
        XCTAssertEqual(mockProjectNetworkService.listCallCount, 1, "Should call list method once")
    }

    func testFetchAll_WithEmptyResponse_HandlesGracefully() async throws {
        // Given
        let localProjects = createMockProjects(count: 3)
        mockPersistenceManager.mockProjects = localProjects

        let emptyResponse = PaginatedResponse(
            items: [],
            hasNext: false,
            totalItems: 0,
            currentPage: 1,
            pageSize: 20
        )
        mockProjectNetworkService.mockPaginatedResponse = emptyResponse

        var remoteDataCalled = false
        var receivedProjects: [Project] = []

        // When
        projectDomainService.fetchAll(
            localData: { _ in },
            remoteData: { projects in
                remoteDataCalled = true
                receivedProjects = projects
            }
        )

        // Wait for async operations
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertTrue(remoteDataCalled, "Remote data should be called")
        XCTAssertEqual(receivedProjects.count, 0, "Should receive empty projects list")
    }

    func testFetchAll_WithNetworkError_ReturnsLocalData() async throws {
        // Given
        let localProjects = createMockProjects(count: 5)
        mockPersistenceManager.mockProjects = localProjects

        mockProjectNetworkService.shouldThrowError = true

        var remoteDataCalled = false
        var receivedProjects: [Project] = []

        // When
        projectDomainService.fetchAll(
            localData: { _ in },
            remoteData: { projects in
                remoteDataCalled = true
                receivedProjects = projects
            }
        )

        // Wait for async operations
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertTrue(remoteDataCalled, "Remote data should be called with fallback")
        XCTAssertEqual(receivedProjects.count, 5, "Should return local projects as fallback")
    }
    // MARK: - Helper Methods

    private func createMockProjects(count: Int) -> [Project] {
        return (0..<count).map { index in
            let projectModel = Project.ProjectModel(
                uuid: "project-\(index)",
                name: "Project \(index)",
                channels: nil,
                team: nil,
                isExpanded: true,
                createdAt: Date(),
                modifiedAt: Date()
            )
            return Project(model: projectModel)
        }
    }

    private func createMockProjectDTOs(count: Int) -> [ProjectDTO] {
        return (0..<count).map { index in
            ProjectDTO(
                id: "project-\(index)",
                title: "Project \(index)",
                description: "Description \(index)",
                teamId: "team-\(index)",
                channelCount: 0,
                projectStatus: "active",
                createdAt: Date(),
                updatedAt: Date()
            )
        }
    }
}

// MARK: - Mock Classes

private class MockProjectNetworkService: ProjectNetworkService {
    var networkManager: NetworkManager = MockNetworkManager()

    var listCalled = false
    var lastTeamId: String = ""
    var lastPage: Int = 0
    var lastPageSize: Int = 0
    var listCallCount = 0
    var mockPaginatedResponse: PaginatedResponse<ProjectDTO>?
    var shouldThrowError = false

    func list(teamId: String, page: Int, pageSize: Int) async throws -> PaginatedResponse<ProjectDTO> {
        listCalled = true
        lastTeamId = teamId
        lastPage = page
        lastPageSize = pageSize
        listCallCount += 1

        if shouldThrowError {
            throw NetworkError(message: "Network error")
        }

        guard let response = mockPaginatedResponse else {
            throw NetworkError(message: "No mock response configured")
        }

        return response
    }

    func create(teamId: String, title: String, description: String?) async throws -> ProjectDTO {
        throw NetworkError(message: "Not implemented")
    }

    func read(teamId: String, projectId: String) async throws -> ProjectDTO {
        throw NetworkError(message: "Not implemented")
    }

    func update(teamId: String, projectId: String, title: String?, description: String?, projectStatus: ProjectStatus) async throws -> ProjectDTO {
        throw NetworkError(message: "Not implemented")
    }

    func delete(teamId: String, projectId: String) async throws {
        throw NetworkError(message: "Not implemented")
    }
}

private class MockPersistenceManager: PersistenceManager {
    var mockProjects: [Project] = []
    var mockChannels: [Channel] = []
    var mockMessages: [Message] = []

    func update<D>(domain: D) async throws where D: Domain, D.S.D == D {
        // Mock implementation
    }

    func update<D>(domains: [D]) async throws where D: Domain, D.S.D == D {
        // Mock implementation
    }

    func fetchItem<D>(persistentIdentifier: PersistentIdentifier) async throws -> D where D: Domain, D.S.D == D {
        // Mock implementation - return first item of requested type
        if D.self == Project.self {
            return mockProjects.first as! D
        }
        throw PersistenceError.missingDomainForIdentifier
    }

    func fetchItem<D>(persistentIdentifier: PersistentIdentifier?) async throws -> D where D: Domain, D.S.D == D {
        return try await fetchItem(persistentIdentifier: persistentIdentifier!)
    }

    func fetchItem<D>(uid: UID) async throws -> D where D: Domain, D.S.D == D {
        // Mock implementation - return first item of requested type
        if D.self == Project.self {
            return mockProjects.first as! D
        }
        throw PersistenceError.missingDomainForIdentifier
    }

    func insert<D>(domain: D) async throws -> D where D: Domain, D.S.D == D {
        // Mock implementation
        return domain
    }

    func query<D>() async throws -> [D] where D: Domain, D.S.D.M == D.M {
        // Mock implementation - return appropriate mock data
        if D.self == Project.self {
            return mockProjects as! [D]
        }
        return []
    }

    func query<D>(predicate: Predicate<D.S>?) async throws -> [D] where D: Domain, D.S.D.M == D.M {
        return try await query()
    }

    func query<D>(sortDescriptors: [SortDescriptor<D.S>]) async throws -> [D] where D: Domain, D.M == D.S.D.M {
        return try await query()
    }

    func query<D>(predicate: Predicate<D.S>?, sortDescriptors: [SortDescriptor<D.S>]) async throws -> [D] where D: Domain, D.S.D.M == D.M {
        return try await query()
    }

    func delete<D>(domain: D) async throws where D: Domain, D.S.D == D {
        // Mock implementation
    }

    func logout() async throws {
        // Mock implementation
    }
}

private struct NetworkError: Error {
    let message: String
}
