import SwiftUI

extension SuggestionType {
    var displayName: String {
        switch self {
//        case .SHAKESPEARE: return "Shakespeare"
        case .OPTIMIZE: return "Optimize"
        case .GPT: return "GPT"
//        case .REDACTION: return "Redaction"
        case .SUMMARIZE: return "Summarize"
        case .ENHANCE: return "Enhance"
        }
    }

    var color: String {
        switch self {
//        case .SHAKESPEARE: return "#FF6B6B"
        case .OPTIMIZE: return "#4ECDC4"
        case .GPT: return "#45B7D1"
//        case .REDACTION: return "#96CEB4"
        case .SUMMARIZE: return "#FFEAA7"
        case .ENHANCE: return "#FFA7EA"
        }
    }
}
struct DetailedSuggestionCard: View {
    let suggestion: Suggestion
    @EnvironmentObject var dashboardState: DashboardStateModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(suggestion.model.suggestionType?.displayName ?? "n/a", systemImage: "textformat.abc.dottedunderline")
                    .font(.caption)
                    .foregroundColor(Color(hex: suggestion.model.suggestionType?.color ?? "#FFFFFF"))
                Label(suggestion.model.application, systemImage: "apple.terminal")
                    .font(.caption)
                    .foregroundColor(Color(hex: suggestion.model.suggestionType?.color ?? "#FFFFFF"))
                
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
