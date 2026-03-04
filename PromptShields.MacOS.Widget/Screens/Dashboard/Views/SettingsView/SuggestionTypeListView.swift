import SwiftUI
import os

/// View displaying a list of suggestion types with CRUD operations
struct SuggestionTypeListView: View {
    // MARK: - Environment

    @Environment(\.suggestionDomainService) private var suggestionDomainService
    @Environment(\.userPreferencesDomainService) private var userPreferencesDomainService

    // MARK: - State

    @StateObject private var suggestionTypesQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.sortOrder, order: .forward)],
        mapping: DefaultMapping<SuggestionType>.self
    )

    @State private var isLoading: Bool = true
    @State private var isResetting: Bool = false
    @State private var showingAddSheet: Bool = false
    @State private var showingResetConfirmation: Bool = false
    @State private var selectedSuggestionType: SuggestionType?
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SuggestionTypeListView.self)
    )

    // MARK: - Computed Properties

    private var suggestionTypes: [SuggestionType] {
        suggestionTypesQueryable.wrappedValue.sorted { a, b in
            a.model.sortOrder < b.model.sortOrder
        }
    }

    private var groupedSuggestionTypes: [String: [SuggestionType]] {
        Dictionary(grouping: suggestionTypes) { $0.model.category }
    }

    private var sortedCategories: [String] {
        let order = ["Writing Clarity", "Structure & Adaptation", "Security & Compliance", "Custom"]
        return groupedSuggestionTypes.keys.sorted { a, b in
            let aIndex = order.firstIndex(of: a) ?? Int.max
            let bIndex = order.firstIndex(of: b) ?? Int.max
            return aIndex < bIndex
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerView

                if isLoading {
                    loadingView
                } else if suggestionTypes.isEmpty {
                    emptyStateView
                } else {
                    listView
                }
                footerView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadData()
        }
        .sheet(isPresented: $showingAddSheet) {
            SuggestionTypeEditorView { _ in
                Task {
                    await suggestionTypesQueryable.refresh()
                }
            }
        }
        .sheet(item: $selectedSuggestionType) { suggestionType in
            SuggestionTypeEditorView(suggestionType: suggestionType) { _ in
                Task {
                    await suggestionTypesQueryable.refresh()
                }
            } onDelete: {
                Task {
                    await suggestionTypesQueryable.refresh()
                }
            }
        }
        .alert("Reset to Defaults", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task {
                    await resetToDefaults()
                }
            }
        } message: {
            Text("This will delete all your custom suggestion types and restore the default set. This action cannot be undone.")
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggestion Types")
                    .font(.headline)

                Text("Customize how your text is transformed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                showingAddSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .help("Add new suggestion type")
        }
        .padding()
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Loading suggestion types...")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Suggestion Types")
                .font(.title2)
                .fontWeight(.medium)

            Text("Add custom suggestion types or reset to defaults.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Add Custom Type") {
                    showingAddSheet = true
                }
                .buttonStyle(.borderedProminent)

                Button("Reset to Defaults") {
                    showingResetConfirmation = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - List View

    private var listView: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(sortedCategories, id: \.self) { category in
                categorySection(category: category, types: groupedSuggestionTypes[category] ?? [])
            }
        }
        .padding()
    }

    private func categorySection(category: String, types: [SuggestionType]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(categoryDisplayName(category))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 4) {
                ForEach(types, id: \.model.uuid) { suggestionType in
                    suggestionTypeRow(suggestionType)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }

    private func suggestionTypeRow(_ suggestionType: SuggestionType) -> some View {
        HStack(spacing: 12) {
            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(suggestionType.model.name)
                        .font(.body)
                        .fontWeight(.medium)

                    if suggestionType.model.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }

                if !suggestionType.model.description.isEmpty {
                    Text(suggestionType.model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { suggestionType.model.isEnabled },
                set: { newValue in
                    Task {
                        await toggleSuggestionType(suggestionType, isEnabled: newValue)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            // Edit button
            Button {
                selectedSuggestionType = suggestionType
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Edit suggestion type")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Footer View

    private var footerView: some View {
        VStack(spacing: 8) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            if let success = successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal)
            }

            HStack {
                Text("\(suggestionTypes.count) types • \(suggestionTypes.filter { $0.model.isEnabled }.count) enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    showingResetConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Defaults")
                    }
                    .font(.caption)
                }
                .buttonStyle(.link)
                .disabled(isResetting)
            }
            .padding()
        }
    }

    // MARK: - Helper Methods

    private func categoryDisplayName(_ category: String) -> String {
        switch category {
        case "Writing Clarity":
            return "🚀 Writing Clarity"
        case "Structure & Adaptation":
            return "⚙️ Structure & Adaptation"
        case "Security & Compliance":
            return "🔒 Security & Compliance"
        case "Custom":
            return "✨ Custom"
        default:
            return category
        }
    }

    // MARK: - Data Operations

    @MainActor
    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            try await suggestionDomainService.fetchSuggestionTypes()
            await suggestionTypesQueryable.refresh()
        } catch {
            logger.error("Failed to load suggestion types: \(error)")
            errorMessage = "Failed to load suggestion types"
        }

        isLoading = false
    }

    @MainActor
    private func toggleSuggestionType(_ suggestionType: SuggestionType, isEnabled: Bool) async {
        do {
            _ = try await suggestionDomainService.toggleSuggestionType(suggestionType, isEnabled: isEnabled)
            await suggestionTypesQueryable.refresh()
        } catch {
            logger.error("Failed to toggle suggestion type: \(error)")
            errorMessage = "Failed to update suggestion type"
        }
    }

    @MainActor
    private func resetToDefaults() async {
        isResetting = true
        errorMessage = nil
        successMessage = nil

        do {
            let count = try await suggestionDomainService.resetSuggestionTypes()
            await suggestionTypesQueryable.refresh()
            successMessage = "Reset complete! \(count) default types restored."

            // Clear success message after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            successMessage = nil
        } catch {
            logger.error("Failed to reset suggestion types: \(error)")
            errorMessage = "Failed to reset suggestion types"
        }

        isResetting = false
    }
}

// MARK: - SuggestionType Identifiable Conformance

extension SuggestionType: Identifiable {
    var id: String {
        model.uuid
    }
}

// MARK: - Preview

#Preview {
    SuggestionTypeListView()
        .frame(width: 400, height: 600)
}
