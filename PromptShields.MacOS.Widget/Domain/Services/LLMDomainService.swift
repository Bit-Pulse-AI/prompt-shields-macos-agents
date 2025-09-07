import SwiftData
import SwiftUI

extension EnvironmentValues {
    var llmDomainService: LLMDomainServiceImpl {
        get { self[LLMDomainServiceKey.self] }
        set { self[LLMDomainServiceKey.self] = newValue }
    }
}

enum LLMProvider: String {
    case AZURE_PROMPTSHIELDS = "AZURE_PROMPTSHIELDS"
    case GOOGLE = "GOOGLE"
struct LLMDomainServiceKey: EnvironmentKey {
    static let defaultValue = {
        return LLMDomainServiceImpl()
    }()
}

protocol LLMDomainService: Sendable {
    func getAvailableLLMs() async throws
}

struct LLMDomainServiceImpl: LLMDomainService {
    @Inject
    private var persistenceManager: PersistenceManager
    @Inject
    private var llmNetworkService: LLMNetworkService
    
    func getAvailableLLMs() async throws {
        let result = try await llmNetworkService.getAvailableLLMs()
        let llms = result.toDomain()
        try await persistenceManager.insert(domains: llms)
    }
}
