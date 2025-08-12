import Foundation
import os

enum DecodingError: Error {
    case noNeedToDecodeData
}

protocol NetworkManager: Sendable {
    @discardableResult
    func perform(
        request: URLRequest
    ) async throws -> Data
}

actor NetworkManagerImpl: NetworkManager {
    // MARK: - Private Properties
    
    private let session: URLSessionProtocol
    private let logger: Logger
    
    static let shared = NetworkManagerImpl()
    
    init(
        session: URLSessionProtocol = URLSession.shared,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!,
            category: String(describing: NetworkManagerImpl.self)
        )
    ) {
        self.session = session
        self.logger = logger
    }
    
    @discardableResult
    func perform(request: URLRequest) async throws -> Data {
        do {
            logger.debug("REQUEST: \(request.httpMethod ?? "") \n request \(request.url?.absoluteString ?? "")")
            let (data, response) = try await session.dataTask(with: request)
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError(message: "Invalid response type")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError(message: "HTTP \(httpResponse.statusCode): Invalid server response")
            }
            
            // Log response for debugging
            logResponse(data: data)
            return data
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError(message: "Request failed: \(error.localizedDescription)")
        }
    }
    
    private func logResponse(data: Data) {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers)
            let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            let response = String(decoding: jsonData, as: UTF8.self)
            logger.debug("Response: \(response)")
        } catch {
            let response = String(decoding: data, as: UTF8.self)
            logger.error("JSON data malformed: \(response)")
            logger.error("Failed to log response: \(error.localizedDescription)")
        }
    }
}
