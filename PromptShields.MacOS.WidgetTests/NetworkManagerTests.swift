import Testing
import Foundation
@testable import PromptShields_MacOS_Widget

/// Unit tests for NetworkManager using SUT (System Under Test) pattern
/// Tests network requests, error handling, and response processing
struct NetworkManagerTests {
    // MARK: - Test Properties

    /// Mock URL session for testing
    private var mockURLSession: MockURLSession!

    /// Mock JSON coder for testing
    private var mockJSONCoder: MockJSONCoder!

    /// Mock logger for testing
    private var mockLogger: MockLogger!

    /// System Under Test - NetworkManager instance being tested
    private var sut: NetworkManager!

    // MARK: - Test Setup

    /// Sets up test environment before each test
    @Test("Setup test environment")
    func setupTestEnvironment() async throws {
        mockURLSession = MockURLSession()
        mockJSONCoder = MockJSONCoder()
        mockLogger = MockLogger()

        sut = NetworkManager(
            session: mockURLSession,
            jsonCoder: mockJSONCoder,
            logger: mockLogger
        )
    }

    // MARK: - JSON Request Tests

    /// Tests successful JSON request
    @Test("Successful JSON request should return decoded response")
    func testSuccessfulJSONRequest() async throws {
        // Given: Valid request and response
        let testResponse = TestResponse(id: 1, name: "Test")
        let testData = try JSONEncoder().encode(testResponse)

        mockURLSession.mockDataTaskResult = .success((testData, createMockHTTPResponse(statusCode: 200)))
        mockJSONCoder.mockEncodeResult = .success(Data())
        mockJSONCoder.mockDecodeResult = .success(testResponse)

        // When: Making a JSON request
        let response: TestResponse = try await sut.request(
            url: "https://api.example.com/test",
            method: .POST,
            body: TestRequest(name: "Test"),
            queryParameters: nil,
            headers: nil
        )

        // Then: Response should be decoded correctly
        #expect(response.id == testResponse.id)
        #expect(response.name == testResponse.name)
        #expect(mockURLSession.dataTaskCallCount == 1)
        #expect(mockJSONCoder.encodeCallCount == 1)
        #expect(mockJSONCoder.decodeCallCount == 1)
    }

    /// Tests JSON request with query parameters
    @Test("JSON request should include query parameters")
    func testJSONRequestWithQueryParameters() async throws {
        // Given: Request with query parameters
        let testResponse = TestResponse(id: 1, name: "Test")
        let testData = try JSONEncoder().encode(testResponse)

        mockURLSession.mockDataTaskResult = .success((testData, createMockHTTPResponse(statusCode: 200)))
        mockJSONCoder.mockEncodeResult = .success(Data())
        mockJSONCoder.mockDecodeResult = .success(testResponse)

        // When: Making a request with query parameters
        let _: TestResponse = try await sut.request(
            url: "https://api.example.com/test",
            method: .GET,
            body: nil,
            queryParameters: ["page": "1", "limit": "10"],
            headers: nil
        )

        // Then: URL should include query parameters
        #expect(mockURLSession.lastRequest?.url?.absoluteString.contains("page=1") == true)
        #expect(mockURLSession.lastRequest?.url?.absoluteString.contains("limit=10") == true)
    }

    /// Tests JSON request with custom headers
    @Test("JSON request should include custom headers")
    func testJSONRequestWithCustomHeaders() async throws {
        // Given: Request with custom headers
        let testResponse = TestResponse(id: 1, name: "Test")
        let testData = try JSONEncoder().encode(testResponse)

        mockURLSession.mockDataTaskResult = .success((testData, createMockHTTPResponse(statusCode: 200)))
        mockJSONCoder.mockEncodeResult = .success(Data())
        mockJSONCoder.mockDecodeResult = .success(testResponse)

        let customHeaders = ["Authorization": "Bearer token", "Content-Type": "application/json"]

        // When: Making a request with custom headers
        let _: TestResponse = try await sut.request(
            url: "https://api.example.com/test",
            method: .POST,
            body: TestRequest(name: "Test"),
            queryParameters: nil,
            headers: customHeaders
        )

        // Then: Request should include custom headers
        #expect(mockURLSession.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    // MARK: - Form Data Request Tests

    /// Tests successful form data request
    @Test("Successful form data request should return decoded response")
    func testSuccessfulFormDataRequest() async throws {
        // Given: Valid form data request and response
        let testResponse = TestResponse(id: 1, name: "Test")
        let testData = try JSONEncoder().encode(testResponse)

        mockURLSession.mockDataTaskResult = .success((testData, createMockHTTPResponse(statusCode: 200)))
        mockJSONCoder.mockDecodeResult = .success(testResponse)

        let parameters = [
            RequestParameterDTO(key: "name", value: "Test"),
            RequestParameterDTO(key: "email", value: "test@example.com")
        ]

        // When: Making a form data request
        let response: TestResponse = try await sut.request(
            url: "https://api.example.com/test",
            method: .POST,
            queryParameters: nil,
            parameters: parameters,
            bodyEncoding: .form,
            headers: nil,
            files: nil
        )

        // Then: Response should be decoded correctly
        #expect(response.id == testResponse.id)
        #expect(mockURLSession.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    }

    // MARK: - Multipart Request Tests

    /// Tests successful multipart request
    @Test("Successful multipart request should return decoded response")
    func testSuccessfulMultipartRequest() async throws {
        // Given: Valid multipart request and response
        let testResponse = TestResponse(id: 1, name: "Test")
        let testData = try JSONEncoder().encode(testResponse)

        mockURLSession.mockDataTaskResult = .success((testData, createMockHTTPResponse(statusCode: 200)))
        mockJSONCoder.mockDecodeResult = .success(testResponse)

        let parameters = [RequestParameterDTO(key: "name", value: "Test")]
        let files = [RequestParameterFileDTO(key: "file", filename: "test.txt", data: Data())]

        // When: Making a multipart request
        let response: TestResponse = try await sut.request(
            url: "https://api.example.com/test",
            method: .POST,
            queryParameters: nil,
            parameters: parameters,
            bodyEncoding: .multipartFormData,
            headers: nil,
            files: files
        )

        // Then: Response should be decoded correctly
        #expect(response.id == testResponse.id)
        #expect(mockURLSession.lastRequest?.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
    }

    // MARK: - Error Handling Tests

    /// Tests network error handling
    @Test("Should handle network errors")
    func testNetworkErrorHandling() async throws {
        // Given: Network error
        mockURLSession.mockDataTaskResult = .failure(NetworkError(message: "Network connection failed"))

        // When & Then: Should throw network error
        do {
            let _: TestResponse = try await sut.request(
                url: "https://api.example.com/test",
                method: .GET,
                body: nil,
                queryParameters: nil,
                headers: nil
            )
            #expect(false, "Should have thrown an error")
        } catch let error as NetworkError {
            #expect(error.message.contains("Network connection failed"))
        } catch {
            #expect(false, "Unexpected error: \(error)")
        }
    }

    /// Tests HTTP error status code handling
    @Test("Should handle HTTP error status codes")
    func testHTTPErrorStatusCodes() async throws {
        // Given: HTTP error response
        let testData = Data()
        mockURLSession.mockDataTaskResult = .success((testData, createMockHTTPResponse(statusCode: 404)))

        // When & Then: Should throw HTTP error
        do {
            let _: TestResponse = try await sut.request(
                url: "https://api.example.com/test",
                method: .GET,
                body: nil,
                queryParameters: nil,
                headers: nil
            )
            #expect(false, "Should have thrown an error")
        } catch let error as NetworkError {
            #expect(error.message.contains("HTTP 404"))
        } catch {
            #expect(false, "Unexpected error: \(error)")
        }
    }

    /// Tests invalid URL handling
    @Test("Should handle invalid URLs")
    func testInvalidURLHandling() async throws {
        // Given: Invalid URL

        // When & Then: Should throw URL error
        do {
            let _: TestResponse = try await sut.request(
                url: "invalid-url",
                method: .GET,
                body: nil,
                queryParameters: nil,
                headers: nil
            )
            #expect(false, "Should have thrown an error")
        } catch let error as NetworkError {
            #expect(error.message.contains("Invalid URL"))
        } catch {
            #expect(false, "Unexpected error: \(error)")
        }
    }

    /// Tests JSON encoding error handling
    @Test("Should handle JSON encoding errors")
    func testJSONEncodingErrorHandling() async throws {
        // Given: JSON encoding error
        mockJSONCoder.mockEncodeResult = .failure(EncodingError.invalidValue("", EncodingError.Context(codingPath: [], debugDescription: "Invalid value")))

        // When & Then: Should throw encoding error
        do {
            let _: TestResponse = try await sut.request(
                url: "https://api.example.com/test",
                method: .POST,
                body: TestRequest(name: "Test"),
                queryParameters: nil,
                headers: nil
            )
            #expect(false, "Should have thrown an error")
        } catch {
            #expect(true, "Expected encoding error")
        }
    }

    /// Tests JSON decoding error handling
    @Test("Should handle JSON decoding errors")
    func testJSONDecodingErrorHandling() async throws {
        // Given: JSON decoding error
        let testData = Data()
        mockURLSession.mockDataTaskResult = .success((testData, createMockHTTPResponse(statusCode: 200)))
        mockJSONCoder.mockDecodeResult = .failure(DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Data corrupted")))

        // When & Then: Should throw decoding error
        do {
            let _: TestResponse = try await sut.request(
                url: "https://api.example.com/test",
                method: .GET,
                body: nil,
                queryParameters: nil,
                headers: nil
            )
            #expect(false, "Should have thrown an error")
        } catch {
            #expect(true, "Expected decoding error")
        }
    }

    // MARK: - Helper Methods

    /// Creates a mock HTTP response for testing
    private func createMockHTTPResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.com/test")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
    }
}

// MARK: - Test Models

/// Test request model for testing
struct TestRequest: Codable {
    let name: String
}

/// Test response model for testing
struct TestResponse: Codable {
    let id: Int
    let name: String
}

// MARK: - Mock Implementations

/// Mock URL session for testing
private class MockURLSession: URLSessionProtocol {
    var mockDataTaskResult: Result<(Data, URLResponse), Error> = .failure(NetworkError(message: "Mock error"))
    var dataTaskCallCount = 0
    var lastRequest: URLRequest?

    func dataTask(with request: URLRequest) async throws -> (Data, URLResponse) {
        dataTaskCallCount += 1
        lastRequest = request

        switch mockDataTaskResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

/// Mock JSON coder for testing
private class MockJSONCoder: JSONCodingProtocol {
    var mockEncodeResult: Result<Data, Error> = .failure(EncodingError.invalidValue("", EncodingError.Context(codingPath: [], debugDescription: "Mock error")))
    var mockDecodeResult: Result<Any, Error> = .failure(DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Mock error")))

    var encodeCallCount = 0
    var decodeCallCount = 0

    func encode<T: Encodable>(_ value: T) throws -> Data {
        encodeCallCount += 1
        switch mockEncodeResult {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        }
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        decodeCallCount += 1
        switch mockDecodeResult {
        case .success(let result as T):
            return result
        case .failure(let error):
            throw error
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Mock error"))
        }
    }
}
