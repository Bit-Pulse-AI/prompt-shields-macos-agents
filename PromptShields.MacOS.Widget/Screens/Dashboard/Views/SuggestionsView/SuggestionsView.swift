import SwiftUI
import os

struct SuggestionsView: View {
    @StateObject private var suggestionsQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
        mapping: DefaultMapping<Suggestion>.self
    )
    @StateObject private var suggestionsTypeQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.suggestionName, order: .reverse)],
        mapping: DefaultMapping<SuggestionType>.self
    )
    @State private var isLoading: Bool = false
    @Environment(\.suggestionDomainService) private var suggestionDomainService
    
    private var suggestionsTypes: [SuggestionType] {
        return suggestionsTypeQueryable.wrappedValue
    }
    private var currentSuggestions: [Suggestion] {
        return suggestionsQueryable.wrappedValue
    }
    
    var hasCurrentSuggestions: Bool {
        currentSuggestions.count > 0
    }
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SettingsView.self)
    )
    
    var body: some View {
        VStack(spacing: 16) {
            if !hasCurrentSuggestions {
                emptyStateView
            } else {
                suggestionsList
            }
        }
        .padding()
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        isLoading = true
        do {
            try await suggestionDomainService.fetchSuggestionTypes()
            isLoading = false
        } catch {
            logger.error("Error fetching user details \(error)")
            isLoading = false
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "textformat.abc.dottedunderline")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Suggestions")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Start typing in any text field to see writing suggestions.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var suggestionsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(currentSuggestions, id: \.identifier) { suggestion in
                    DetailedSuggestionCard(suggestion: suggestion) { type in
                        suggestionsTypes.first { $0.model.suggestionType == type }?.model.suggestionName ?? "n/a"
                    }
                }
            }
        }
    }
}
