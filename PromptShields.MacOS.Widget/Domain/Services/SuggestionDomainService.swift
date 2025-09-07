import SwiftData
import SwiftUI
import Foundation
import os

extension EnvironmentValues {
    var suggestionDomainService: SuggestionDomainServiceImpl {
        get { self[SuggestionDomainServiceKey.self] }
        set { self[SuggestionDomainServiceKey.self] = newValue }
    }
}

struct SuggestionDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return SuggestionDomainServiceImpl()
    }()
}

protocol SuggestionDomainService: Sendable {
    @discardableResult
    func process(text: String,
                 llmProvider: String,
                 suggestionGroupId: String,
                 suggestionType: String,
                 application: String) async throws -> Suggestion
    func fetchSuggestionTypes() async throws
    func list(suggestionGroupId: String,
              llmProvider: String,
              teamId: String,
              offset: Int,
              limit: Int) async throws
}

struct SuggestionDomainServiceImpl: SuggestionDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var suggestionNetworkService: SuggestionNetworkService
    
    private let path = "suggestion"
    
    @discardableResult
    func process(text: String,
                 llmProvider: String,
                 suggestionGroupId: String,
                 suggestionType: String,
                 application: String) async throws -> Suggestion {
        let suggestionResult = try await suggestionNetworkService.process(text: text,
                                                                          llmProvider: llmProvider,
                                                                          suggestionGroupId: suggestionGroupId,
                                                                          suggestionType: suggestionType,
                                                                          application: application)
        let suggestion = suggestionResult.toDomain()
        try await persistenceManager.insert(domain: suggestion)
        return suggestion
    }
    
    func list(suggestionGroupId: String,
              llmProvider: String,
              teamId: String,
              offset: Int,
              limit: Int) async throws {
//        let suggestionsResult = try await suggestionNetworkService
//            .list(
//                suggestionGroupId: suggestionGroupId,
//                llmProvider: llmProvider,
//                teamId: teamId,
//                offset: offset,
//                limit: limit)
//        persistenceManager.inser
    }
    
    func fetchSuggestionTypes() async throws {
        let suggestionResult = try await suggestionNetworkService.fetchSuggestionTypes()
        let suggestion = suggestionResult.toDomain()
        try await persistenceManager.deleteEntity(entity: SuggestionType.self)
        try await persistenceManager.insert(domains: suggestion)
    }
}
