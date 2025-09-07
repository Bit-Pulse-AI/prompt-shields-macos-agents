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
                        // Suggestion Types
                        suggestionTypesSection(preferences)
                        
                        // Application Blocking
//                        applicationBlockingSection(preferences)
                        
                        // UI Settings
//                        uiSettingsSection(preferences)
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
                                        preferences
                                            .model
                                            .enabledSuggestionTypes
                                            .contains(suggestionType.model.suggestionType)
                                    },
                                    set: { newValue in
                                        var newTypes = preferences.model.enabledSuggestionTypes
                                        if newValue {
                                            newTypes.append(suggestionType.model.suggestionType)
                                        } else {
                                            newTypes.removeAll(where: {
                                                $0 == suggestionType.model.suggestionType
                                            })
                                        }
                                        var newPreferences = preferences
                                        newPreferences.model.enabledSuggestionTypes = newTypes
                                        Task { @Sendable in
                                            try await updatePreferences(newPreferences)
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
    
    private func applicationBlockingSection(_ preferences: UserPreferences) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blocked Applications")
                .font(.headline)

            Text("Applications where suggestions are disabled")
                .font(.caption)
                .foregroundColor(.secondary)

            if preferences.model.blockedApplications.isEmpty {
                Text("No applications blocked")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(preferences.model.blockedApplications, id: \.self) { app in
                        HStack {
                            Text(app)
                            Spacer()
                            Button("Remove") {
                                var newBlocked = preferences.model.blockedApplications
                                newBlocked.removeAll { blockedApp in
                                    blockedApp == app
                                }
                                var newPreferences = preferences
                                newPreferences.model.blockedApplications = newBlocked
                                Task { @Sendable in
                                    try await updatePreferences(newPreferences)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func uiSettingsSection(_ preferences: UserPreferences) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interface")
                .font(.headline)
            
            VStack(spacing: 8) {
                Picker("Panel position", selection: Binding(
                    get: { preferences.model.panelPosition },
                    set: { newValue in
                        var newPreferences = preferences
                        newPreferences.model.panelPosition = newValue
                        Task {
                            try await updatePreferences(newPreferences)
                        }
                    }
                )) {
                    ForEach(PanelPosition.allCases, id: \.self) { position in
                        Text(position.displayName).tag(position)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func loadData() async {
        isLoading = true
        do {
            let preferences = try await userPreferencesDomainService.currentUserPreferences
            self.preferences = preferences
            try await suggestionDomainService.fetchSuggestionTypes()
            isLoading = false
        } catch {
            logger.error("Error fetching user details \(error)")
            isLoading = false
        }
    }
    
    @MainActor
    private func updatePreferences(_ newPreferences: UserPreferences) async throws {
        try await userPreferencesDomainService.savePreferences(preferences: newPreferences)
        self.preferences = newPreferences
    }
}
