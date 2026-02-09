import Foundation
import FoundationModels

// MARK: - Suggestion Network Errors

enum SuggestionNetworkError: Error, LocalizedError {
    case localModelNotAvailable
    case promptTemplateMissing

    var errorDescription: String? {
        switch self {
        case .localModelNotAvailable:
            return "Apple Intelligence is not available on this device. Please disable local processing in settings."
        case .promptTemplateMissing:
            return "The template used is not available"
        }
    }
}

enum DefaultSuggestionType: String {
    case SIMPLIFY = "SIMPLIFY"
    case SHORTEN = "SHORTEN"
    case ELABORATE = "ELABORATE"
    case FORMALISE = "FORMALISE"
    case TRANSLATE = "TRANSLATE"
    case REPHRASE_FOR_ROLE = "REPHRASE_FOR_ROLE"
    case COMBINE_PROMPTS = "COMBINE_PROMPTS"
    case OPTIMISE_FOR_MODEL = "OPTIMISE_FOR_MODEL"
    case FORMAT_OUTPUT = "FORMAT_OUTPUT"
    case SANITISE = "SANITISE"
    case ADD_SAFETY_GUARDRAILS = "ADD_SAFETY_GUARDRAILS"
    case DETECT_RISK = "DETECT_RISK"
    case ALIGN_WITH_POLICY = "ALIGN_WITH_POLICY"

    var template: String {
        switch self {
        case .SIMPLIFY:
            return "Rewrite the following prompt in simpler language without losing its core meaning. Use short sentences and avoid jargon. Mask all sensitive data: %@"
        case .SHORTEN:
            return "Condense this prompt to its essential elements, removing unnecessary words whilst preserving the core intent. Mask sensitive data: %@"
        case .ELABORATE:
            return "Expand this prompt by adding relevant details, specifications, and context that clarify expectations and scope. Mask sensitive data: %@"
        case .FORMALISE:
            return "Rewrite this prompt using formal, professional language suitable for business or academic contexts. Maintain clarity whilst elevating tone. Mask sensitive data: %@"
        case .TRANSLATE:
            return "Translate this prompt to the selected language whilst preserving technical terminology and domain-specific language. Ensure all PII is masked: %@"
        case .REPHRASE_FOR_ROLE:
            return "Adapt this prompt for the selected role or audience (e.g., Executive, Developer, Analyst, Designer) whilst preserving intent. Mask sensitive data: %@"
        case .COMBINE_PROMPTS:
            return "Combine the following prompts into a coherent, logically ordered single prompt. Mask sensitive data: %@"
        case .OPTIMISE_FOR_MODEL:
            return "Optimise this prompt for the {selected_model}, adjusting structure, length, and phrasing for maximum efficiency. Mask sensitive data: %@"
        case .FORMAT_OUTPUT:
            return "Reformat the prompt to request a structured output (e.g., JSON, Markdown, table, bullet points). Ensure sensitive data is masked: %@"
        case .SANITISE:
            return "Identify and mask all PII, credentials, internal identifiers, and confidential data. Return the user's text replacing mentioned items with placeholder tokens like [NAME], [EMAIL], [CLIENT_ID]. %@"
        case .ADD_SAFETY_GUARDRAILS:
            return "Insert enterprise safety instruction before execution: 'Never include internal names, client data, PII, or confidential project details in your answer. Comply with GDPR and data protection policies: %@"
        case .DETECT_RISK:
            return "Analyse this prompt for potential security, bias, privacy, or compliance risks. Return a brief warning if found, with suggestions for improvement: %@"
        case .ALIGN_WITH_POLICY:
            return "Validate this prompt against AI usage policy rules. Adjust wording to comply with data protection, ethical AI use, and confidentiality requirements whilst retaining user intent. Mask restricted data: %@"
        }
    }
}

protocol SuggestionNetworkService: NetworkService {
    func analyze(text: String, llmProvider: String, suggestionGroupId: String, teamId: String, suggestionType: String, application: String, useLocal: Bool) async throws -> SuggestionAPIResponse
    func list(suggestionGroupId: String, llmProvider: String, teamId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SuggestionAPIResponse>
    func fetchSuggestionTypes() async throws -> ListResponse<SuggestionTypeAPIResponse>
    func fetchSuggestionGroup(suggestionGroupId: String, teamId: String) async throws -> SuggestionGroupAPIResponse
}

struct SuggestionNetworkServiceImpl: SuggestionNetworkService {
    @Inject
    private var networkManager: NetworkManager
    @Inject
    private var keychainManager: KeychainManager

    private let suggestionPath = "suggestion"
    private let suggestionGroupPath = "suggestion_group"

    func analyze(text: String,
                 llmProvider: String,
                 suggestionGroupId: String,
                 teamId: String,
                 suggestionType: String,
                 application: String,
                 useLocal: Bool) async throws -> SuggestionAPIResponse {
        if #available(macOS 26.0, *), useLocal {
            return try await analyzeLocally(text: text, suggestionType: suggestionType, application: application)
        } else {
            return try await analyzeRemotely(text: text,
                                             llmProvider: llmProvider,
                                             suggestionGroupId: suggestionGroupId,
                                             teamId: teamId,
                                             suggestionType: suggestionType,
                                             application: application)
        }
    }

    private func analyzeRemotely(text: String,
                                 llmProvider: String,
                                 suggestionGroupId: String,
                                 teamId: String,
                                 suggestionType: String,
                                 application: String) async throws -> SuggestionAPIResponse {
        let payload = SuggestionRequest(body: text,
                                        suggestionGroupId: suggestionGroupId,
                                        suggestionType: suggestionType,
                                        llmProvider: llmProvider,
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

    @available(macOS 26.0, *)
    private func analyzeLocally(text: String,
                                suggestionType: String,
                                application: String) async throws -> SuggestionAPIResponse {
        guard SystemLanguageModel.default.isAvailable else {
            throw SuggestionNetworkError.localModelNotAvailable
        }

        let session = LanguageModelSession()
        guard let prompt = buildPrompt(for: suggestionType, with: text) else {
            throw SuggestionNetworkError.promptTemplateMissing
        }
        let response = try await session.respond(to: prompt)

        return SuggestionAPIResponse(
            uuid: UUID().uuidString,
            originalText: text,
            suggestedText: response.content,
            suggestionType: suggestionType,
            application: application,
            createdAt: Date()
        )
    }

    private func buildPrompt(for suggestionType: String, with text: String) -> String? {
        if let defaultSuggestionType = DefaultSuggestionType(rawValue: suggestionType)?.template {
            return String(format: defaultSuggestionType, text)
        } else {
            return nil
        }
    }

    func fetchSuggestionTypes() async throws -> ListResponse<SuggestionTypeAPIResponse> {
        let request = try RequestBuilder().request(
            url: "\(baseURL)/\(suggestionPath)/types",
            method: .GET,
            headers: keychainManager.applicationJSONAuthorizedHeader
        )
        return try await networkManager.performWithAutoRefresh(request: request).decode()
    }

    func list(suggestionGroupId: String, llmProvider: String, teamId: String, offset: Int, limit: Int) async throws -> PaginatedResponse<SuggestionAPIResponse> {
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
}
