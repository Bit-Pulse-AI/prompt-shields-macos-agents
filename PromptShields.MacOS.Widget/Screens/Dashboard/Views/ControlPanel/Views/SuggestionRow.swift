import SwiftUI

struct SuggestionRowView: View {
    let suggestion: Suggestion
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: suggestion.model.type.color))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.model.suggestion)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(suggestion.model.type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(Int(suggestion.model.confidence * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
