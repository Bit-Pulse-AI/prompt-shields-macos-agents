import SwiftUI
import os

/// Settings view with editable suggestion types and user preferences
struct SettingsView: View {
    @Environment(\.userDomainService) private var userDomainService
    @Environment(\.userPreferencesDomainService) private var userPreferencesDomainService
    @Environment(\.suggestionDomainService) private var suggestionDomainService

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SettingsView.self)
    )

    var body: some View {
        VStack(spacing: 0) {
            SuggestionTypeListView()
        }
    }
}
