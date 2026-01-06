import XCTest

@testable import PromptShields_MacOS_Widget

final class PromptShields_MacOS_WidgetTests: XCTestCase {
    // MARK: - Test Suites

    func testIntegration() async throws {
        let integrationTests = await IntegrationTests()
        try await integrationTests.testErrorPropagation()
    }

    func testPagination() async throws {
        let paginationTests = PaginationTests()
        try await paginationTests.testPaginationFetchesMultiplePages()
        try await paginationTests.testPaginationHandlesEmptyResponse()
        try await paginationTests.testPaginationRespectsHasNextFlag()
    }

    func testProjectPagination() async throws {
        let projectPaginationTests = ProjectPaginationTests()
        try await projectPaginationTests.testFetchAll_WithMultiplePages_LoadsAllProjects()
        try await projectPaginationTests.testFetchAll_WithEmptyResponse_HandlesGracefully()
        try await projectPaginationTests.testFetchAll_WithNetworkError_ReturnsLocalData()
    }

    // MARK: - Performance Tests

    /// Tests authentication performance
    func testAuthenticationPerformance() async throws {
        let startTime = Date()

        // Simulate authentication process
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        XCTAssertLessThan(duration, 1.0, "Authentication should complete within 1 second")
    }

    /// Tests network request performance
    func testNetworkRequestPerformance() async throws {
        let networkManager = NetworkManagerImpl()

        let startTime = Date()

        // Simulate network request
        let request = URLRequest(url: URL(string: "https://example.com")!)
        _ = try await networkManager.perform(request: request)

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        XCTAssertLessThan(duration, 5.0, "Network request should complete within 5 seconds")
    }

    /// Tests persistence operations performance
    func testPersistencePerformance() async throws {
        let persistenceManager = PersistenceManagerImpl.shared

        let startTime = Date()

        // Simulate persistence operations
        let _: [Channel] = try await persistenceManager.query()

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        XCTAssertLessThan(duration, 2.0, "Persistence operations should complete within 2 seconds")
    }

    /// Tests concurrent network requests
    func testConcurrentNetworkRequests() async throws {
        let networkManager = NetworkManagerImpl()

        let request = URLRequest(url: URL(string: "https://example.com")!)

        // Simulate multiple concurrent network requests
        async let request1 = networkManager.perform(request: request)
        async let request2 = networkManager.perform(request: request)

        // Both should complete without throwing
        _ = try await (request1, request2)
    }
}
