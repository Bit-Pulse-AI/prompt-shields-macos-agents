import Foundation
import os

// MARK: - Request Parameter Types

struct RequestParameter: Sendable {
    let key: String
    let value: String?
}

struct RequestParameterFile: Sendable {
    let key: String
    let filename: String
    let data: Data
}

struct RequestBuilder {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: NetworkManagerImpl.self)
    )

    @discardableResult
    func request<RQ: SendableEncodable>(
        url: String,
        method: HTTPMethod,
        body: RQ? = nil,
        queryParameters: [String: String]? = nil,
        headers: [String: String]? = nil
    ) throws -> URLRequest {
        var request = try buildRequest(
            url: url,
            method: method,
            headers: headers,
            queryParameters: queryParameters
        )

        // Encode body for non-GET methods
        if method != .GET {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let body = body {
                request.httpBody = try JSONEncoder().encode(body)
                logRequestDetails(request: request)
            }
        }

        return request
    }

    @discardableResult
    func request(
        url: String,
        method: HTTPMethod,
        queryParameters: [String: String]? = nil,
        parameters: [RequestParameter]? = nil,
        bodyEncoding: BodyEncoding = .multipartFormData,
        headers: [String: String]? = nil,
        files: [RequestParameterFile]? = nil
    ) throws -> URLRequest {
        var request = try buildRequest(
            url: url,
            method: method,
            headers: headers,
            queryParameters: queryParameters
        )

        // Encode body for non-GET methods
        if method != .GET {
            switch bodyEncoding {
            case .form:
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                if let parameters = parameters {
                    request.httpBody = createFormDataBody(parameters: parameters)
                }
            case .multipartFormData:
                let boundary = "Boundary-\(UUID().uuidString)"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.httpBody = createMultipartBody(
                    parameters: parameters,
                    files: files,
                    boundary: boundary
                )
            }
        }

        return request
    }

//    func uploadRequest(url: String) -> URLRequest {
//        let boundary = UUID().uuidString
//        var request = URLRequest(url: URL(string: "\(baseURL)/files/upload")!)
//        request.httpMethod = "POST"
//        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
//        
//        var body = Data()
//        
//        // Add file data
//        body.append("--\(boundary)\r\n".data(using: .utf8)!)
//        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
//        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
//        body.append(fileData)
//        body.append("\r\n".data(using: .utf8)!)
//        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
//        
//        request.httpBody = body
//        return request
//    }

    private func createMultipartBody(
            parameters: [RequestParameter]?,
            files: [RequestParameterFile]?,
            boundary: String
        ) -> Data {
            var body = Data()

            // Add parameters
            if let parameters = parameters {
                for parameter in parameters {
                    if let value = parameter.value {
                        body.append("--\(boundary)\r\n".data(using: .utf8)!)
                        body.append("Content-Disposition: form-data; name=\"\(parameter.key)\"\r\n\r\n".data(using: .utf8)!)
                        body.append("\(value)\r\n".data(using: .utf8)!)
                    }
                }
            }

            // Add files
            if let files = files {
                for file in files {
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    body.append("Content-Disposition: form-data; name=\"\(file.key)\"; filename=\"\(file.filename)\"\r\n".data(using: .utf8)!)
                    body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
                    body.append(file.data)
                    body.append("\r\n".data(using: .utf8)!)
                }
            }

            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            return body
        }

    private func createFormDataBody(parameters: [RequestParameter]) -> Data? {
        let formString = parameters.compactMap { param -> String? in
            guard let value = param.value else { return nil }
            return "\(param.key)=\(value)"
        }.joined(separator: "&")

        return formString.data(using: .utf8)
    }

    private func buildRequest(
           url: String,
           method: HTTPMethod,
           headers: [String: String]?,
           queryParameters: [String: String]?
       ) throws -> URLRequest {
           guard var urlComponents = URLComponents(string: url) else {
               throw NetworkError(message: "Invalid URL: \(url)")
           }

           if method == .GET, let queryParameters = queryParameters {
               urlComponents.queryItems = queryParameters.map {
                   URLQueryItem(name: $0.key, value: $0.value)
               }
           }

           guard let finalURL = urlComponents.url else {
               throw NetworkError(message: "Failed to construct URL with query parameters")
           }

           var request = URLRequest(url: finalURL)
           request.httpMethod = method.rawValue

           // Set headers
           if let headers = headers {
               for (key, value) in headers {
                   request.setValue(value, forHTTPHeaderField: key)
               }
           }

           return request
       }

    private func logRequestDetails(request: URLRequest) {
        logger.debug("Request URL: \(request.url?.absoluteString ?? "nil")")
        logger.debug("Request Method: \(request.httpMethod ?? "nil")")
        logger.debug("Request Headers: \(request.allHTTPHeaderFields ?? [:])")
        logger.debug("Request Body: \(request.httpBody.string ?? "nil")")
    }
//
//    func request(url: String, method: HTTPMethod, headers: [String : String]?) async throws -> Data {
//        let request = try buildRequest(url: url, method: method, headers: headers, queryParameters: nil)
//        return try await performRequest(request: request)
//    }
//
//    func request(request: URLRequest) async throws -> FileDTO {
//        try await performRequest(request: request).decode()
//    }

}
//
// extension NetworkManagerImpl {
//    func request<RE: SendableDecodable, RQ: SendableEncodable>(url: String, method: HTTPMethod, body: RQ?, headers: [String: String]?) async throws -> RE where RE: SendableDecodable, RQ: SendableEncodable {
//        try await request(url: url, method: method, body: body, queryParameters: nil, headers: headers)
//    }
//
//    func request<RE: SendableDecodable>(url: String, method: HTTPMethod, headers: [String: String]?) async throws -> RE where RE: SendableDecodable {
//        let body: DummySE? = nil
//        return try await request(url: url, method: method, body: body, queryParameters: nil, headers: headers)
//    }
//
//    func request(url: String, method: HTTPMethod, headers: [String: String]?) async throws {
//        let body: DummySE? = nil
//        let _: DummySD = try await request(url: url, method: method, body: body, queryParameters: nil, headers: headers)
//    }
// }
