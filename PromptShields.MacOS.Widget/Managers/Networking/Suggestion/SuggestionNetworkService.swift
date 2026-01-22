import Foundation

// MARK: - Request Models

struct CreateSuggestionTypeRequest: SendableEncodable {
    let typeKey: String
    let name: String
    let description: String
    let category: String
    let promptTemplate: String
    let suggestionTypeGroupId: String
    let icon: String
    let isEnabled: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case typeKey = "type_key"
        case name
        case description
        case category
        case suggestionTypeGroupId = "suggestion_type_group_id"
        case promptTemplate = "prompt_template"
        case icon
        case isEnabled = "is_enabled"
        case sortOrder = "sort_order"
    }
}

struct UpdateSuggestionTypeRequest: SendableEncodable {
    var name: String?
    var description: String?
    var category: String?
    var promptTemplate: String?
    var icon: String?
    var isEnabled: Bool?
    var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case category
        case promptTemplate = "prompt_template"
        case icon
        case isEnabled = "is_enabled"
        case sortOrder = "sort_order"
    }

    // Custom encoding to skip nil values
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let name { try container.encode(name, forKey: .name) }
        if let description { try container.encode(description, forKey: .description) }
        if let category { try container.encode(category, forKey: .category) }
        if let promptTemplate { try container.encode(promptTemplate, forKey: .promptTemplate) }
        if let icon { try container.encode(icon, forKey: .icon) }
        if let isEnabled { try container.encode(isEnabled, forKey: .isEnabled) }
        if let sortOrder { try container.encode(sortOrder, forKey: .sortOrder) }
    }
}

struct ResetSuggestionTypesResponse: Decodable {
    let message: String
    let count: Int
}

// MARK: - Protocol

protocol SuggestionNetworkService: NetworkService {
    func analyze(text: String, suggestionGroupId: String, teamId: String, suggestionType: String, application: String) async throws -> SuggestionAPIResponse
    func list(suggestionGroupId: String, teamId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SuggestionAPIResponse>
    func analyze(text: String, llmProvider: String, suggestionGroupId: String, teamId: String, suggestionType: String, application: String) async throws -> SuggestionAPIResponse
    func listSuggestions(suggestionGroupId: String, llmProvider: String, teamId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SuggestionAPIResponse>
    func fetchSuggestionGroup(suggestionGroupId: String, teamId: String) async throws -> SuggestionGroupAPIResponse
    func fetchSuggestionTypeGroup(suggestionTypeGroupId: String, teamId: String) async throws -> SuggestionTypeGroupAPIResponse
    func listSuggestionTypes(suggestionTypeGroupId: String, offset: Int, limit: Int, enabledOnly: Bool) async throws -> PaginatedResponse<SuggestionTypeAPIResponse>
    func getSuggestionType(suggestionTypeGroupId: String) async throws -> SuggestionTypeAPIResponse
    func createSuggestionType(request: CreateSuggestionTypeRequest) async throws -> SuggestionTypeAPIResponse
    func updateSuggestionType(_ suggestionTypeGroupId: String, suggestionTypeId: String, request payload: UpdateSuggestionTypeRequest) async throws -> SuggestionTypeAPIResponse
    func deleteSuggestionType(_ suggestionTypeGroupId: String, suggestionTypeId: String) async throws
    func toggleSuggestionType(suggestionTypeGroupId: String, suggestionTypeId: String, isEnabled: Bool) async throws -> SuggestionTypeAPIResponse
    func resetSuggestionTypes(suggestionTypeGroupId: String) async throws -> ResetSuggestionTypesResponse
}

// MARK: - Implementation

struct SuggestionNetworkServiceImpl: SuggestionNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager

    private let suggestionPath = "suggestion"
    private let suggestionTypesPath = "suggestion-types"

    // MARK: - Legacy Suggestion Analysis

    func analyze(text: String,
                 suggestionGroupId: String,
                 teamId: String,
                 suggestionType: String,
                 application: String) async throws -> SuggestionAPIResponse {
        let payload = SuggestionRequest(body: text,
                                        suggestionGroupId: suggestionGroupId,
                                        suggestionType: suggestionType,
                                        teamId: teamId,
                                        application: application)
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionPath)/analyze/",
            method: .POST,
            body: payload,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    func fetchSuggestionTypeGroup(suggestionTypeGroupId: String, teamId: String) async throws -> SuggestionTypeGroupAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/teams/\(teamId)/suggestion_type_group/\(suggestionTypeGroupId)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    func list(suggestionGroupId: String, teamId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SuggestionAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/teams/\(teamId)/suggestion_group/\(suggestionGroupId)/suggestions",
            method: .GET,
            queryParameters: ["offset": "\(offset)", "limit": "\(limit)"],
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    func fetchSuggestionGroup(suggestionGroupId: String, teamId: String) async throws -> SuggestionGroupAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/teams/\(teamId)/suggestion_group/\(suggestionGroupId)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    func listSuggestions(suggestionGroupId: String, llmProvider: String, teamId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SuggestionAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/teams/\(teamId)/suggestion_group/\(suggestionGroupId)/suggestions",
            method: .GET,
            queryParameters: ["offset": "\(offset)", "limit": "\(limit)"],
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    // MARK: - Suggestion Type CRUD Operations

    func listSuggestionTypes(suggestionTypeGroupId: String, offset: Int, limit: Int, enabledOnly: Bool) async throws -> PaginatedResponse<SuggestionTypeAPIResponse> {
        var queryParams: [String: String] = [
            "offset": "\(offset)",
            "limit": "\(limit)"
        ]
        if enabledOnly {
            queryParams["enabled_only"] = "true"
        }

        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionTypesPath)/\(suggestionTypeGroupId)",
            method: .GET,
            queryParameters: queryParams,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    func getSuggestionType(suggestionTypeGroupId: String) async throws -> SuggestionTypeAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionTypesPath)/\(suggestionTypeGroupId)",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    func createSuggestionType(request payload: CreateSuggestionTypeRequest) async throws -> SuggestionTypeAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionTypesPath)/",
            method: .POST,
            body: payload,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    func updateSuggestionType(_ suggestionTypeGroupId: String, suggestionTypeId: String, request payload: UpdateSuggestionTypeRequest) async throws -> SuggestionTypeAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionTypesPath)/\(suggestionTypeGroupId)/suggestion-type-id/\(suggestionTypeId)",
            method: .PUT,
            body: payload,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    func deleteSuggestionType(_ suggestionTypeGroupId: String, suggestionTypeId: String) async throws {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionTypesPath)/\(suggestionTypeGroupId)/suggestion-type-id/\(suggestionTypeId)",
            method: .DELETE,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        _ = try await networkManager.performWithAutoRefresh(request: request)
    }

    func toggleSuggestionType(suggestionTypeGroupId: String, suggestionTypeId: String, isEnabled: Bool) async throws -> SuggestionTypeAPIResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionTypesPath)/\(suggestionTypeGroupId)/suggestion-type-id/\(suggestionTypeId)/toggle",
            method: .PATCH,
            queryParameters: ["is_enabled": "\(isEnabled)"],
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    func resetSuggestionTypes(suggestionTypeGroupId: String) async throws -> ResetSuggestionTypesResponse {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionTypesPath)/\(suggestionTypeGroupId)/reset",
            method: .POST,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }
}
