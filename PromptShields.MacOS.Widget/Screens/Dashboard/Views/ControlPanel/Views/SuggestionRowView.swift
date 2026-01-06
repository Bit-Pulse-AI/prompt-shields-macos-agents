import SwiftUI

struct SuggestionRowView: View {
    let suggestion: Suggestion

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: "#4ECDC4"))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.model.suggestedText)
                    .font(.body)
                    .fontWeight(.medium)

                Text(suggestion.model.suggestionType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
