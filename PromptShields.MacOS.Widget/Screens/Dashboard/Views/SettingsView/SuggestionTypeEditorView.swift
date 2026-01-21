import SwiftUI
import os

/// View for creating or editing a suggestion type
/// The prompt template wraps around the user's selected text using {{TEXT}} as a placeholder
struct SuggestionTypeEditorView: View {
    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.suggestionDomainService) private var suggestionDomainService
    @Environment(\.profileDomainService) private var profileDomainService

    // MARK: - State

    @State private var typeKey: String
    @State private var name: String
    @State private var description: String
    @State private var category: String
    @State private var promptTemplate: String
    @State private var icon: String
    @State private var isEnabled: Bool
    @State private var sortOrder: Int

    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var showingDeleteConfirmation: Bool = false

    // MARK: - Properties

    private let existingSuggestionType: SuggestionType?
    private let isEditing: Bool
    private let onSave: ((SuggestionType) -> Void)?
    private let onDelete: (() -> Void)?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SuggestionTypeEditorView.self)
    )

    private let categories = [
        "Writing Clarity",
        "Structure & Adaptation",
        "Security & Compliance",
        "Custom"
    ]

    private let commonIcons = ["💡", "✂️", "📝", "🔤", "🌍", "👤", "🔗", "⚡", "📄", "🧹", "🛡️", "⚠️", "✅", "✨", "🎯", "🔧", "📊", "🎨"]

    // MARK: - Initialization

    init(suggestionType: SuggestionType? = nil, onSave: ((SuggestionType) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.existingSuggestionType = suggestionType
        self.isEditing = suggestionType != nil
        self.onSave = onSave
        self.onDelete = onDelete

        // Initialize state with existing values or defaults
        _typeKey = State(initialValue: suggestionType?.model.typeKey ?? "")
        _name = State(initialValue: suggestionType?.model.name ?? "")
        _description = State(initialValue: suggestionType?.model.description ?? "")
        _category = State(initialValue: suggestionType?.model.category ?? "Custom")
        _promptTemplate = State(initialValue: suggestionType?.model.promptTemplate ?? "")
        _icon = State(initialValue: suggestionType?.model.icon ?? "✨")
        _isEnabled = State(initialValue: suggestionType?.model.isEnabled ?? true)
        _sortOrder = State(initialValue: suggestionType?.model.sortOrder ?? 99)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    basicInfoSection
                    promptSection
                    settingsSection

                    if isEditing {
                        deleteSection
                    }
                }
                .padding()
            }

            Divider()

            // Footer with action buttons
            footerView
        }
        .frame(width: 500, height: 600)
        .alert("Delete Suggestion Type", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await deleteSuggestionType()
                }
            }
        } message: {
            Text("Are you sure you want to delete this suggestion type? This action cannot be undone.")
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Text(isEditing ? "Edit Suggestion Type" : "New Suggestion Type")
                .font(.headline)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Basic Info Section

    private let spacing: CGFloat = 10
    private let minCell: CGFloat = 30

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic Information")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            // Icon picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Icon")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: minCell), spacing: spacing)],
                    spacing: spacing
                ) {
                    ForEach(commonIcons.enumerated().compactMap { $0.offset }, id: \.self) { index in
                        let commonIcon = commonIcons[index]
                        Button {
                            icon = commonIcon
                        } label: {
                            Text(commonIcon)
                                .font(.title2)
                                .padding(4)
                                .background(icon == commonIcon ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Enter name (e.g., Simplify)", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            // Type Key (only for new types)
            if !isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type Key")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Enter unique key (e.g., MY_CUSTOM_TYPE)", text: $typeKey)
                        .textFieldStyle(.roundedBorder)
                        .textCase(.uppercase)

                    Text("This is a unique identifier and cannot be changed after creation")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Description
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Optional description", text: $description)
                    .textFieldStyle(.roundedBorder)
            }

            // Category
            VStack(alignment: .leading, spacing: 4) {
                Text("Category")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Category name", text: $category)
                    .textFieldStyle(.roundedBorder)
                .pickerStyle(.menu)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prompt Template")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("This template wraps around your selected text. Use the placeholder to indicate where your text will be inserted.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Placeholder insertion button
                HStack {
                    Button {
                        insertPlaceholder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.insert")
                            Text("Insert Text Placeholder")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(placeholderIsPresent ? Color.gray.opacity(0.3) : Color.accentColor.opacity(0.2))
                        .foregroundColor(placeholderIsPresent ? .secondary : .accentColor)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(placeholderIsPresent)

                    if placeholderIsPresent {
                        Label("Placeholder added", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Spacer()
                }

                PromptTemplateEditor(text: $promptTemplate)
                    .frame(minHeight: 150)

                HStack {
                    Text("\(promptTemplate.count) / 5000 characters")
                        .font(.caption2)
                        .foregroundColor(promptTemplate.count > 5000 ? .red : .secondary)

                    Spacer()

                    if !placeholderIsPresent {
                        Label("Add \(SuggestionType.textPlaceholder) to specify where your text will be inserted", systemImage: "info.circle")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Placeholder Helpers

    private var placeholderIsPresent: Bool {
        promptTemplate.contains(SuggestionType.textPlaceholder)
    }

    private func insertPlaceholder() {
        if !placeholderIsPresent {
            // Insert at the end if not present
            if promptTemplate.isEmpty {
                promptTemplate = SuggestionType.textPlaceholder
            } else {
                promptTemplate += "\n\n\(SuggestionType.textPlaceholder)"
            }
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Toggle("Enabled", isOn: $isEnabled)

            HStack {
                Text("Sort Order")
                Spacer()
                Stepper("\(sortOrder)", value: $sortOrder, in: 0...999)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Danger Zone")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.red)

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Suggestion Type")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Button(isEditing ? "Save Changes" : "Create") {
                Task {
                    await saveSuggestionType()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || isSaving)
            .keyboardShortcut(.return)
        }
        .padding()
    }

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !promptTemplate.trimmingCharacters(in: .whitespaces).isEmpty &&
        promptTemplate.count <= 5000 &&
        (isEditing || !typeKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Actions

    @MainActor
    private func saveSuggestionType() async {
        guard isValid else { return }

        isSaving = true
        errorMessage = nil

        guard let profile = try? await profileDomainService.currentProfile else {
            return
        }
        do {
            let model = SuggestionType.SuggestionTypeModel(
                uuid: existingSuggestionType?.model.uuid ?? UUID().uuidString,
                typeKey: isEditing ? existingSuggestionType!.model.typeKey : typeKey.uppercased().replacingOccurrences(of: " ", with: "_"),
                name: name.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespaces),
                category: category,
                promptTemplate: promptTemplate,
                suggestionTypeGroupId: profile.model.defaultSuggestionTypeGroupId,
                icon: icon,
                isDefault: existingSuggestionType?.model.isDefault ?? false,
                isEnabled: isEnabled,
                sortOrder: sortOrder,
                createdAt: existingSuggestionType?.model.createdAt,
                updatedAt: Date()
            )

            let suggestionType = SuggestionType(
                model: model,
                identifier: existingSuggestionType?.identifier
            )

            let savedType: SuggestionType
            if isEditing {
//                savedType = try await suggestionDomainService.updateSuggestionType(suggestionType)
            } else {
                savedType = try await suggestionDomainService.createSuggestionType(suggestionType)
            }

//            onSave?(savedType)
            dismiss()
        } catch {
            logger.error("Failed to save suggestion type: \(error)")
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    @MainActor
    private func deleteSuggestionType() async {
        guard let existingType = existingSuggestionType else {
            return
        }
        isSaving = true
        errorMessage = nil

        do {
            try await suggestionDomainService.deleteSuggestionType(existingType)
            onDelete?()
            dismiss()
        } catch {
            logger.error("Failed to delete suggestion type: \(error)")
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }

        isSaving = false
    }
}

// MARK: - Preview

#Preview {
    SuggestionTypeEditorView()
}
