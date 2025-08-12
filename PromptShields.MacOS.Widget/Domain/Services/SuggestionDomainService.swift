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
}

struct SuggestionDomainServiceImpl: SuggestionDomainService {
}
