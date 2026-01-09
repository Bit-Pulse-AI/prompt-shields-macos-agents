import SwiftUI
import os

struct SettingsView: View {
    @Environment(\.userDomainService) private var userDomainService
    @Environment(\.userPreferencesDomainService) private var userPreferencesDomainService
    @Environment(\.suggestionDomainService) private var suggestionDomainService
    @State private var isLoading = false
    @State private var preferences: UserPreferences?
    @StateObject private var suggestionTypesQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.suggestionName, order: .forward)],
        mapping: DefaultMapping<SuggestionType>.self
    )
    private var suggestionTypes: [SuggestionType] {
        suggestionTypesQueryable.wrappedValue.sorted { a, b in
            a.model.suggestionName < b.model.suggestionName
        }
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SettingsView.self)
    )

    var body: some View {
        VStack(spacing: .zero) {
            if !isLoading, let preferences = preferences {
                ScrollView {
                    VStack(spacing: 20) {
                        suggestionTypesSection(preferences)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: .zero) {
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadData()
        }
    }

    private func suggestionTypesSection(_ preferences: UserPreferences) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggestion Types")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestionTypes, id: \.model.uuid) { suggestionType in
                    HStack {
                        Toggle(suggestionType.model.suggestionName,
                               isOn:
                                Binding(
                                    get: {
                                        let suggestionTypes = preferences
                                            .model
                                            .enabledSuggestionTypes
                                        return ((suggestionTypes?.contains(suggestionType.model.suggestionType)) != nil)
                                    },
                                    set: { newValue in
                                        var newTypes = preferences.model.enabledSuggestionTypes
                                        if newValue {
                                            newTypes?.append(suggestionType.model.suggestionType)
                                        } else {
                                            newTypes?.removeAll(where: {
                                                $0 == suggestionType.model.suggestionType
                                            })
                                        }
                                        var newPreferences = preferences
                                        newPreferences.model.enabledSuggestionTypes = newTypes
                                        Task { @MainActor in
                                            try? await updatePreferences(newPreferences)
                                        }
                                    }
                        ))
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 350)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    @MainActor
    private func loadData() async {
        isLoading = true
        do {
            let preferences = try await userPreferencesDomainService.currentUserPreferences()
            self.preferences = preferences
            try await suggestionDomainService.fetchSuggestionTypes()
        } catch {
            logger.debug("Error fetching user details \(error)")
        }
        isLoading = false
    }

    @MainActor
    private func updatePreferences(_ newPreferences: UserPreferences) async throws {
        try await userPreferencesDomainService.savePreferences(preferences: newPreferences)
        self.preferences = newPreferences
    }
}
