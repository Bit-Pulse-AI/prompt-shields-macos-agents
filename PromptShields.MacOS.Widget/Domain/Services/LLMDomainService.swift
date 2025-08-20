import SwiftData
import SwiftUI

extension EnvironmentValues {
    var llmDomainService: LLMDomainServiceImpl {
        get { self[LLMDomainServiceKey.self] }
        set { self[LLMDomainServiceKey.self] = newValue }
    }
}

struct LLMDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return LLMDomainServiceImpl()
    }()
}

protocol LLMDomainService: Sendable {
    func process(text: String, llmProvider: LLMProvider, suggestionType: SuggestionType, application: String) async throws -> String
}

enum LLMProvider: String {
    case AZURE_PROMPTSHIELDS = "AZURE_PROMPTSHIELDS"
    case GOOGLE = "GOOGLE"
}

enum SuggestionType: String, CaseIterable {
    case OPTIMIZE = "OPTIMIZE"
    case GPT = "GPT"
    case SUMMARIZE = "SUMMARIZE"
    case ENHANCE = "ENHANCE"
}

struct LLMDomainServiceImpl: LLMDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var llmNetworkService: LLMNetworkService
    
    func process(text: String, llmProvider: LLMProvider, suggestionType: SuggestionType, application: String) async throws -> String {
        let result = try await llmNetworkService.process(text: text, llmProvider: llmProvider.rawValue, suggestionType: suggestionType.rawValue, application: application)
        try await persistenceManager.insert(domain: result.toDomain())
        return result.suggestedText
    }
}
