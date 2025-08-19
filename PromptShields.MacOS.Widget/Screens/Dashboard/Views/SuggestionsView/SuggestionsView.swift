import SwiftUI

struct SuggestionsView: View {
    @StateObject private var suggestionsQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
        mapping: DefaultMapping<Suggestion>.self
    )
    
    private var currentSuggestions: [Suggestion] {
        return suggestionsQueryable.wrappedValue
    }
    
    var hasCurrentSuggestions: Bool {
        currentSuggestions.count > 0
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if !hasCurrentSuggestions {
                emptyStateView
            } else {
                suggestionsList
            }
        }
        .padding()
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
                    DetailedSuggestionCard(suggestion: suggestion)
                }
            }
        }
    }
}
