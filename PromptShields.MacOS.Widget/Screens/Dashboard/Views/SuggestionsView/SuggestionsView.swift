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
    @State private var isLoadingNextPage: Bool = false
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
            await loadInitialData()
        }
    }
    
    private func loadInitialData() async {
        isLoading = true
        do {
            try await suggestionDomainService.fetchSuggestionTypes()
            try await suggestionDomainService.list(offset: 0, limit: 2)
        } catch {
            logger.error("Error fetching user details \(error)")
        }
        try? await Task.sleep(for: .seconds(1))
        isLoading = false
    }
    
    private func loadNextPage() async {
        do {
            isLoadingNextPage = true
            try await suggestionDomainService.list(offset: currentSuggestions.count, limit: 2)
        } catch {
            logger.error("Error fetching next page \(error)")
        }
        try? await Task.sleep(for: .seconds(1))
        isLoadingNextPage = false
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
            if isLoading {
                HStack(alignment: .center) {
                    ProgressView()
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(currentSuggestions, id: \.identifier) { suggestion in
                        DetailedSuggestionCard(suggestion: suggestion) { type in
                            suggestionsTypes.first { $0.model.suggestionType == type }?.model.suggestionName ?? "n/a"
                        }
                        if currentSuggestions.last?.model.uuid == suggestion.model.uuid && !isLoadingNextPage {
                            ProgressView()
                                .task {
                                    await loadNextPage()
                                }
                        }
                    }
                }
            }
        }
    }
}
