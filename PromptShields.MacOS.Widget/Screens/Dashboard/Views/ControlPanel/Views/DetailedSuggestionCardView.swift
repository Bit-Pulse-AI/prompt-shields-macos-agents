import SwiftUI

struct DetailedSuggestionCard: View {
    let suggestion: Suggestion
    @EnvironmentObject var dashboardState: DashboardStateModel
    let suggestionName: (String) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(suggestionName(suggestion.model.suggestionType), systemImage: "textformat.abc.dottedunderline")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label(suggestion.model.application, systemImage: "apple.terminal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            // Original Text
            VStack(alignment: .leading, spacing: 4) {
                Text("Original")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(suggestion.model.originalText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Suggestion
            VStack(alignment: .leading, spacing: 4) {
                Text("Suggestion")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(suggestion.model.suggestedText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}
