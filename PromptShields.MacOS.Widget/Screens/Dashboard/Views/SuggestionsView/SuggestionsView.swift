import SwiftUI
import os

@MainActor
struct SuggestionsView: View {
    @StateObject private var suggestionsQueryable = ObservableQueryable(
        sortDescriptors: [],
        mapping: DefaultMapping<Suggestion>.self
    )
    @StateObject private var suggestionsTypeQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.sortOrder, order: .forward)],
        mapping: DefaultMapping<SuggestionType>.self
    )
    @StateObject private var currentSuggestionGroupQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.title, order: .reverse)],
        mapping: DefaultMapping<SuggestionGroup>.self
    )
    @State private var isLoadingNextPage: Bool = false
    @State private var isLoading: Bool = true

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
        category: String(describing: SuggestionsView.self)
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

    @MainActor
    private func loadInitialData() async {
        isLoading = true
        do {
            let suggestionGroup = try await suggestionDomainService.fetchCurrentSuggestionGroup()
            let totalSuggestions = suggestionGroup.model.suggestionCount

            // Explicitly refresh queryables to pick up any cached data
            await suggestionsQueryable.refresh()
            await suggestionsTypeQueryable.refresh()
            await currentSuggestionGroupQueryable.refresh()

            guard currentSuggestions.count < totalSuggestions && totalSuggestions > 0 else {
                isLoading = false
                return
            }
            let numberOfItemsPerPage = min(suggestionsPerPage, totalSuggestions - currentSuggestions.count)
            try await suggestionDomainService.fetchSuggestionTypes()
            try await suggestionDomainService.list(offset: 0, limit: numberOfItemsPerPage)

            // Refresh again after data is written
            await suggestionsQueryable.refresh()
            await suggestionsTypeQueryable.refresh()
        } catch {
            logger.debug("Error fetching user details \(error)")
        }

        // Small delay to let UI settle
        try? await Task.sleep(for: .milliseconds(300))
        isLoading = false
    }

    @MainActor
    private func loadNextPageIfNeeded() async {
        guard !isLoadingNextPage else { return }
        isLoadingNextPage = true
        do {
            let suggestionGroup = try await suggestionDomainService.fetchCurrentSuggestionGroup()
            let totalSuggestions = suggestionGroup.model.suggestionCount
            guard currentSuggestions.count < totalSuggestions && totalSuggestions > 0 else {
                isLoadingNextPage = false
                return
            }
            let numberOfItemsPerPage = min(suggestionsPerPage, totalSuggestions - currentSuggestions.count)
            try await suggestionDomainService.list(offset: currentSuggestions.count, limit: numberOfItemsPerPage)

            // Explicitly refresh after data is written
            await suggestionsQueryable.refresh()
        } catch {
            logger.debug("Error fetching next page \(error)")
        }

        // Small delay to let UI settle
        try? await Task.sleep(for: .milliseconds(300))
        isLoadingNextPage = false
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if isLoading {
                HStack(alignment: .center) {
                    ProgressView()
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
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
                        DetailedSuggestionCard(suggestion: suggestion) { typeKey in
                            // Find suggestion type by typeKey and return its display name
                            suggestionsTypes.first { $0.model.typeKey == typeKey }?.displayName ?? typeKey
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
