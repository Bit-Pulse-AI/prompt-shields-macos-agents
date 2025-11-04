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
    @StateObject private var currentSuggestionGroupQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.title, order: .reverse)],
        mapping: DefaultMapping<SuggestionGroup>.self
    )
    @State private var isLoadingNextPage: Bool = false
    @State private var isLoading: Bool = false

    @Environment(\.suggestionDomainService) private var suggestionDomainService

    private var currentSuggestionGroup: SuggestionGroup? {
        return currentSuggestionGroupQueryable.wrappedValue.first
    }

    private var suggestionsTypes: [SuggestionType] {
        return suggestionsTypeQueryable.wrappedValue
    }

    private var currentSuggestions: [Suggestion] {
        return suggestionsQueryable.wrappedValue
    }

    private var suggestionsCount: Int {
        currentSuggestionGroup?.model.suggestionCount ?? 0
    }

    private var hasCurrentSuggestions: Bool {
        currentSuggestions.count > 0
    }

    private let suggestionsPerPage: Int = 2

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
            let suggestionGroup = try await suggestionDomainService.fetchCurrentSuggestionGroup()
            let totalSuggestions = suggestionGroup.model.suggestionCount
            guard currentSuggestions.count < totalSuggestions && totalSuggestions > 0  else {
                isLoading = false
                return
            }
            let numberOfItemsPerPage = min(suggestionsPerPage, totalSuggestions - currentSuggestions.count)
            try await suggestionDomainService.fetchSuggestionTypes()
            try await suggestionDomainService.list(offset: 0, limit: numberOfItemsPerPage)
        } catch {
            isLoading = false
            logger.error("Error fetching user details \(error)")
        }
        try? await Task.sleep(for: .seconds(1))
        isLoading = false
    }

    private func loadNextPageIfNeeded() async {
        do {
            isLoadingNextPage = true
            let suggestionGroup = try await suggestionDomainService.fetchCurrentSuggestionGroup()
            let totalSuggestions = suggestionGroup.model.suggestionCount
            guard currentSuggestions.count < totalSuggestions && totalSuggestions > 0  else {
                isLoading = false
                return
            }
            let numberOfItemsPerPage = min(suggestionsPerPage, totalSuggestions - currentSuggestions.count)
            try await suggestionDomainService.list(offset: currentSuggestions.count, limit: numberOfItemsPerPage)
        } catch {
            isLoading = false
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
                        if currentSuggestions.last?.model.uuid == suggestion.model.uuid && currentSuggestions.count < suggestionsCount {
                            ProgressView()
                                .task {
                                    await loadNextPageIfNeeded()
                                }
                        }
                    }
                }
            }
        }
    }
}
