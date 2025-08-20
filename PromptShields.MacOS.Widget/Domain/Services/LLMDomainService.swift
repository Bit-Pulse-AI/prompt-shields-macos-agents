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
    
    // Limit the number of suggestions to keep in memory
    private let maxSuggestionsToKeep = 100
    
    func process(text: String, llmProvider: LLMProvider, suggestionType: SuggestionType, application: String) async throws -> String {
        let result = try await llmNetworkService.process(text: text, llmProvider: llmProvider.rawValue, suggestionType: suggestionType.rawValue, application: application)
        
        // Insert the new suggestion
//        try await persistenceManager.insert(domain: result.toDomain())
        
        // Clean up old suggestions to prevent memory accumulation
        await cleanupOldSuggestions()
        
        return result.suggestedText
    }
    
    private func cleanupOldSuggestions() async {
        do {
            // Get all suggestions sorted by creation date (oldest first)
            let allSuggestions: [Suggestion] = try await persistenceManager.query(
                sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)]
            )
            
            // If we have more than the limit, delete the oldest ones
            if allSuggestions.count > maxSuggestionsToKeep {
                let suggestionsToDelete = Array(allSuggestions.prefix(allSuggestions.count - maxSuggestionsToKeep))
                try await persistenceManager.delete(domains: suggestionsToDelete)
            }
        } catch {
            // Log error but don't fail the main operation
            print("Failed to cleanup old suggestions: \(error)")
        }
    }
}
