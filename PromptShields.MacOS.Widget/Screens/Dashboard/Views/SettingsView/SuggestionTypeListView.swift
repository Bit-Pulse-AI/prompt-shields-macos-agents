import SwiftUI
import os

/// View displaying a list of suggestion types with CRUD operations.
/// Per PS-10, each row is expandable — expanded state shows a plain-English
/// description and a before/after example pulled from `SuggestionTypeCatalog`.
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
    @State private var expandedTypeIDs: Set<String> = []
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

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: PSSpacing.md) {
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
            Text("SUGGESTION TYPES")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.psText3)

            Spacer()

            Button {
                showingAddSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add type")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.psBlue)
            }
            .buttonStyle(.plain)
            .help("Add a new suggestion type")
        }
        .padding(.horizontal, PSSpacing.xs)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading suggestion types...")
                .font(.caption)
                .foregroundStyle(Color.psText3)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 44))
                .foregroundStyle(Color.psText3)
            Text("No suggestion types")
                .font(.system(size: 16, weight: .semibold))
            Text("Add a custom type or reset to defaults.")
                .font(.system(size: 13))
                .foregroundStyle(Color.psText3)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Add type") { showingAddSheet = true }
                    .buttonStyle(.borderedProminent)
                Button("Reset to defaults") { showingResetConfirmation = true }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PSSpacing.xxl)
    }

    // MARK: - List View

    private var listView: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestionTypes.enumerated()), id: \.element.model.uuid) { index, type in
                SuggestionTypeExpandableRow(
                    suggestionType: type,
                    isExpanded: expandedTypeIDs.contains(type.model.uuid),
                    onToggleExpand: { toggleExpanded(type) },
                    onToggleEnabled: { newValue in
                        Task { await toggleSuggestionType(type, isEnabled: newValue) }
                    },
                    onEdit: { selectedSuggestionType = type },
                    showsDivider: index < suggestionTypes.count - 1
                )
            }
        }
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }

    // MARK: - Footer View

    private var footerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.psRed)
            }
            if let success = successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundStyle(Color.psGreen)
            }

            HStack {
                Text("\(suggestionTypes.count) types • \(suggestionTypes.filter { $0.model.isEnabled }.count) enabled")
                    .font(.caption)
                    .foregroundStyle(Color.psText3)

                Spacer()

                Button {
                    showingResetConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to defaults")
                    }
                    .font(.caption)
                }
                .buttonStyle(.link)
                .disabled(isResetting)
            }
        }
        .padding(.horizontal, PSSpacing.xs)
    }

    // MARK: - Actions

    private func toggleExpanded(_ type: SuggestionType) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedTypeIDs.contains(type.model.uuid) {
                expandedTypeIDs.remove(type.model.uuid)
            } else {
                expandedTypeIDs.insert(type.model.uuid)
            }
        }
    }

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

            try? await Task.sleep(for: .seconds(3))
            successMessage = nil
        } catch {
            logger.error("Failed to reset suggestion types: \(error)")
            errorMessage = "Failed to reset suggestion types"
        }

        isResetting = false
    }
}

// MARK: - Expandable Row

private struct SuggestionTypeExpandableRow: View {
    let suggestionType: SuggestionType
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleEnabled: (Bool) -> Void
    let onEdit: () -> Void
    let showsDivider: Bool

    private var metadata: SuggestionTypeMetadata? {
        SuggestionTypeCatalog.metadata(for: suggestionType)
    }

    private var summaryText: String? {
        if let meta = metadata { return meta.summary }
        let stored = suggestionType.model.description
        return stored.isEmpty ? nil : stored
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if isExpanded {
                detailDrawer
            }
            if showsDivider {
                Divider().background(Color.psBorder)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: PSSpacing.md) {
            Text(metadata?.emoji ?? "✨")
                .font(.system(size: 17))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(suggestionType.model.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.psText)
                    if suggestionType.model.isDefault {
                        Text("Default")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.psBlueLight)
                            .foregroundStyle(Color.psBlue)
                            .clipShape(Capsule())
                    }
                }
                if !isExpanded, let summary = summaryText {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.psText3)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: PSSpacing.md)

            Toggle("", isOn: Binding(
                get: { suggestionType.model.isEnabled },
                set: { onToggleEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.psText3)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Edit suggestion type")

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.psText3)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(.easeInOut(duration: 0.18), value: isExpanded)
                .frame(width: 20, height: 20)
        }
        .padding(.horizontal, PSSpacing.lg)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onToggleExpand() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(suggestionType.model.name)
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
    }

    @ViewBuilder
    private var detailDrawer: some View {
        VStack(alignment: .leading, spacing: PSSpacing.md) {
            if let summary = summaryText {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.psText2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let meta = metadata {
                exampleBox(
                    label: "Before",
                    text: meta.before,
                    background: Color.psRedLight,
                    border: Color.psRed.opacity(0.3),
                    textColor: Color.psRed
                )
                exampleBox(
                    label: "After",
                    text: meta.after,
                    background: Color.psGreenLight,
                    border: Color.psGreen.opacity(0.3),
                    textColor: Color.psGreen
                )
            }
        }
        .padding(.horizontal, PSSpacing.lg)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.psBg)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.psBg3),
            alignment: .top
        )
    }

    private func exampleBox(label: String, text: String, background: Color, border: Color, textColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(textColor.opacity(0.8))
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.psText2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.sm, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
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
