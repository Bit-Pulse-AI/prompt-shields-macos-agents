import SwiftUI

extension SuggestionType {
    var displayName: String {
        switch self {
        case .grammar: return "Grammar"
        case .spelling: return "Spelling"
        case .style: return "Style"
        case .clarity: return "Clarity"
        case .tone: return "Tone"
        }
    }

    var color: String {
        switch self {
        case .grammar: return "#FF6B6B"
        case .spelling: return "#4ECDC4"
        case .style: return "#45B7D1"
        case .clarity: return "#96CEB4"
        case .tone: return "#FFEAA7"
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
                Label(suggestion.model.type.displayName, systemImage: "textformat.abc.dottedunderline")
                    .font(.caption)
                    .foregroundColor(Color(hex: suggestion.model.type.color))
                
                Spacer()
                
                Text("\(Int(suggestion.model.confidence * 100))% confidence")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Original Text
            VStack(alignment: .leading, spacing: 4) {
                Text("Original")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(suggestion.model.text)
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
                
                Text(suggestion.model.suggestion)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Explanation
            if !suggestion.model.explanation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explanation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(suggestion.model.explanation)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            // Actions
            HStack(spacing: 12) {
                Button("Apply") {
                    Task {
//                        [coordinator] in
//                        await coordinator.applySuggestion(suggestion)
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Ignore") {
//                    coordinator.ignoreSuggestion(suggestion)
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}
