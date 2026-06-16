import SwiftUI
import os

// Activity Log (PS-12). Lists every prompt analysis the app has produced,
// grouped by recency. Each entry shows: badge (Risk / Sanitised / Optimised),
// app name, timestamp, and a short snippet.
//
// LIMITATION: PS-12 also asks for an entry per *clean* prompt scan ("no
// sensitive data detected"). The current persistence layer only stores
// `Suggestion` records when an actual suggestion is produced — clean-prompt
// scans aren't emitted by the backend. That belongs to a follow-up backend
// change; the UI here is structured to render those entries the moment they
// start arriving.

@MainActor
struct SuggestionsView: View {
    @StateObject private var suggestionsQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
        mapping: DefaultMapping<Suggestion>.self
    )
    @StateObject private var suggestionsTypeQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.sortOrder, order: .forward)],
        mapping: DefaultMapping<SuggestionType>.self
    )
    @StateObject private var currentSuggestionGroupQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.title, order: .reverse)],
        mapping: DefaultMapping<SuggestionGroup>.self
    )
    @State private var isLoading: Bool = true
    @State private var isLoadingNextPage: Bool = false
    @State private var filter: ActivityFilter = .all

    @Environment(\.suggestionDomainService) private var suggestionDomainService

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SuggestionsView.self)
    )

    private let pageSize: Int = 20

    private var entries: [Suggestion] {
        let all = suggestionsQueryable.wrappedValue
        return all.filter { filter.matches($0) }
    }

    private var totalSuggestions: Int {
        currentSuggestionGroupQueryable.wrappedValue.first?.model.suggestionCount ?? 0
    }

    private var firstPromptVariant: Bool {
        // "First prompt protected!" empty-state variant when exactly one entry exists.
        suggestionsQueryable.wrappedValue.count == 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PSSpacing.lg) {
                header
                if isLoading && entries.isEmpty {
                    loadingView
                } else if entries.isEmpty {
                    emptyState
                } else {
                    if firstPromptVariant {
                        firstPromptBanner
                    }
                    list
                }
            }
            .padding(PSSpacing.panel)
        }
        .background(Color.psBg)
        .task { await loadInitialData() }
    }

    // MARK: - Header (filters)

    private var header: some View {
        VStack(alignment: .leading, spacing: PSSpacing.md) {
            Text("Activity Log")
                .font(.system(size: 21, weight: .regular, design: .serif))
                .foregroundStyle(Color.psText)
            HStack(spacing: 8) {
                ForEach(ActivityFilter.allCases, id: \.self) { option in
                    filterChip(option)
                }
                Spacer()
            }
            .tourAnchor("activity-log-filters")
        }
    }

    private func filterChip(_ option: ActivityFilter) -> some View {
        let selected = filter == option
        return Button {
            filter = option
        } label: {
            Text(option.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? .white : Color.psText2)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(selected ? Color.psBlue : Color.psBg2)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(selected ? Color.psBlue : Color.psBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.model.uuid) { index, suggestion in
                ActivityLogRow(
                    suggestion: suggestion,
                    badge: ActivityBadge.for(suggestion: suggestion),
                    showsDivider: index < entries.count - 1
                )
                .modifier(FirstRowAnchorModifier(isFirst: index == 0))
                .onAppear {
                    if suggestion.model.uuid == entries.last?.model.uuid,
                       suggestionsQueryable.wrappedValue.count < totalSuggestions {
                        Task { await loadNextPageIfNeeded() }
                    }
                }
            }
            if isLoadingNextPage {
                ProgressView()
                    .padding(PSSpacing.lg)
            }
        }
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }

    // MARK: - Empty / loading

    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("Loading activity…")
                .font(.caption)
                .foregroundStyle(Color.psText3)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("📋")
                .font(.system(size: 44))
            Text("No activity yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.psText)
            Text("Activate the shield to start monitoring. Your prompt history will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(Color.psText3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(PSSpacing.xxl)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }

    private var firstPromptBanner: some View {
        HStack(spacing: 10) {
            Text("🎉")
            Text("First prompt protected!")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.psGreen)
            Spacer()
        }
        .padding(.horizontal, PSSpacing.lg)
        .padding(.vertical, 10)
        .background(Color.psGreenLight)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.md, style: .continuous)
                .stroke(Color.psGreen.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Data

    @MainActor
    private func loadInitialData() async {
        isLoading = true
        do {
            let suggestionGroup = try await suggestionDomainService.fetchCurrentSuggestionGroup()
            let total = suggestionGroup.model.suggestionCount

            await suggestionsQueryable.refresh()
            await suggestionsTypeQueryable.refresh()
            await currentSuggestionGroupQueryable.refresh()

            if suggestionsQueryable.wrappedValue.count < total && total > 0 {
                let toFetch = min(pageSize, total - suggestionsQueryable.wrappedValue.count)
                try await suggestionDomainService.fetchSuggestionTypes()
                try await suggestionDomainService.list(offset: 0, limit: toFetch)
                await suggestionsQueryable.refresh()
            }
        } catch {
            logger.debug("Activity log load failed: \(error)")
        }
        try? await Task.sleep(for: .milliseconds(200))
        isLoading = false
    }

    @MainActor
    private func loadNextPageIfNeeded() async {
        guard !isLoadingNextPage else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        do {
            let group = try await suggestionDomainService.fetchCurrentSuggestionGroup()
            let total = group.model.suggestionCount
            let loaded = suggestionsQueryable.wrappedValue.count
            guard loaded < total else { return }
            let toFetch = min(pageSize, total - loaded)
            try await suggestionDomainService.list(offset: loaded, limit: toFetch)
            await suggestionsQueryable.refresh()
        } catch {
            logger.debug("Activity log next page failed: \(error)")
        }
    }
}

// MARK: - Filter

private enum ActivityFilter: CaseIterable {
    case all, riskCaught, sanitised, improved

    var label: String {
        switch self {
        case .all: return "All"
        case .riskCaught: return "Risk caught"
        case .sanitised: return "Sanitised"
        case .improved: return "Improved"
        }
    }

    func matches(_ suggestion: Suggestion) -> Bool {
        let badge = ActivityBadge.for(suggestion: suggestion)
        switch self {
        case .all: return true
        case .riskCaught: return badge == .riskCaught
        case .sanitised: return badge == .sanitised
        case .improved: return badge == .optimised
        }
    }
}

// MARK: - Badge classification

enum ActivityBadge: Equatable {
    case riskCaught, sanitised, optimised

    var label: String {
        switch self {
        case .riskCaught: return "Risk caught"
        case .sanitised: return "Sanitised"
        case .optimised: return "Optimised"
        }
    }

    var foreground: Color {
        switch self {
        case .riskCaught: return Color.psRed
        case .sanitised: return Color.psBlue
        case .optimised: return Color.psGreen
        }
    }

    var background: Color {
        switch self {
        case .riskCaught: return Color.psRed.opacity(0.1)
        case .sanitised: return Color.psBlueMid
        case .optimised: return Color.psGreenLight
        }
    }

    static func `for`(suggestion: Suggestion) -> ActivityBadge {
        let lowered = suggestion.model.suggestionType.lowercased()
        if lowered.contains("risk") || lowered.contains("policy") || lowered.contains("guardrail") {
            return .riskCaught
        }
        if lowered.contains("sanit") {
            return .sanitised
        }
        return .optimised
    }
}

// MARK: - First-row anchor

/// Tags only the first row in the list as `activity-log-first-row` so
/// the activity-log-intro tour can spotlight a specific entry without
/// 50 sibling anchors fighting for the same id.
private struct FirstRowAnchorModifier: ViewModifier {
    let isFirst: Bool
    func body(content: Content) -> some View {
        if isFirst { content.tourAnchor("activity-log-first-row") } else { content }
    }
}

// MARK: - Row

private struct ActivityLogRow: View {
    let suggestion: Suggestion
    let badge: ActivityBadge
    let showsDivider: Bool

    private var meta: String {
        let app = suggestion.model.application.isEmpty ? "Unknown app" : suggestion.model.application
        return "\(app) · \(Self.relative(date: suggestion.model.createdAt))"
    }

    private var snippet: String {
        let text = suggestion.model.suggestedText.isEmpty
            ? suggestion.model.originalText
            : suggestion.model.suggestedText
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 140 ? String(trimmed.prefix(140)) + "…" : trimmed
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                badgePill

                VStack(alignment: .leading, spacing: 4) {
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.psText3)
                    Text(snippet)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.psText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PSSpacing.lg)
            .padding(.vertical, 14)

            if showsDivider {
                Divider().background(Color.psBg3)
            }
        }
    }

    private var badgePill: some View {
        Text(badge.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(badge.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badge.background)
            .clipShape(Capsule())
    }

    private static func relative(date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
