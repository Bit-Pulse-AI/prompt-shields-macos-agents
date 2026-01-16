import SwiftUI
import os

struct ActionView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @Environment(\.suggestionDomainService) private var suggestionDomainService
    @Environment(\.userPreferencesDomainService) private var userPreferencesDomainService
    @Environment(\.profileDomainService) private var profileDomainService

    @StateObject private var suggestionTypesQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.sortOrder, order: .forward)],
        mapping: DefaultMapping<SuggestionType>.self
    )
    @State private var currentUserPreferences: UserPreferences?
    @State private var isProcessing = false
    @State private var isViewActive = true
    @State private var actionText: String = ""
    @State private var injectionError: String?

    /// Text injection service - created once and reused
    private let textInjectionService: TextInjectionService = DefaultTextInjectionService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ActionView.self)
    )

    /// Returns true if the action tool is in an interactive state (not idle)
    private var isInteractive: Bool {
        switch overlayStateModel.actionToolState {
        case .idle:
            return false
        case .loading, .action, .options, .category:
            return true
        }
    }

    private var suggestionTypes: [SuggestionType] {
        let allTypes = suggestionTypesQueryable.wrappedValue
        let enabledFilters = currentUserPreferences?.model.enabledSuggestionTypes

        // Filter to only enabled types (from both the type's isEnabled and user preferences)
        let enabledTypes = allTypes.filter { $0.model.isEnabled }

        // If enabledSuggestionTypes preference is nil, all enabled types are shown
        guard let enabledFilters = enabledFilters else {
            return enabledTypes.sorted { $0.model.sortOrder < $1.model.sortOrder }
        }

        return enabledTypes.filter {
            enabledFilters.contains($0.model.typeKey)
        }.sorted {
            $0.model.sortOrder < $1.model.sortOrder
        }
    }

    private var suggestionCategories: [String] {
        let categories = suggestionTypes.compactMap { $0.model.category }
        let uniqueCategories = Array(Set(categories))

        // Sort categories in a logical order
        let order = ["Writing Clarity", "Structure & Adaptation", "Security & Compliance", "Custom"]
        return uniqueCategories.sorted { a, b in
            let aIndex = order.firstIndex(of: a) ?? Int.max
            let bIndex = order.firstIndex(of: b) ?? Int.max
            return aIndex < bIndex
        }
    }

    var body: some View {
        contentView
            .onAppear {
                isViewActive = true
            }
            .onDisappear {
                isViewActive = false
                isProcessing = false
                accessibilityManager.resumeFromInteraction()
            }
            .onChange(of: overlayStateModel.actionToolState) { oldState, newState in
                handleStateChange(from: oldState, to: newState)
            }
            .task {
                // Ensure suggestion types are loaded when view appears
                await suggestionTypesQueryable.refresh()
            }
    }

    @ViewBuilder
    private var contentView: some View {
        switch overlayStateModel.actionToolState {
        case .idle:
            idleView
        case .loading:
            loadingView
        case .action:
            actionResultView
        case .options(let category):
            optionsView(category: category)
        case .category:
            categoryView
        }
    }

    // MARK: - State Views

    private var idleView: some View {
        Button {
            isProcessing = true
            Task { @MainActor in
                currentUserPreferences = try await userPreferencesDomainService.currentUserPreferences
                overlayStateModel.actionToolState = .category
                isProcessing = false
            }
        } label: {
            Image(ImageResource(name: "logo_mid", bundle: .main))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(ButtonStyleWhite())
        .frame(width: 50, height: 50)
        .cornerRadius(8)
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .controlSize(.small)
        }
        .frame(width: 60, height: 60)
        .background(.white)
        .cornerRadius(8)
    }

    private var actionResultView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(actionText)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)

            if let error = injectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Button {
                    Task { @MainActor in
                        await replaceText()
                    }
                } label: {
                    Text("Agree & Update")
                        .font(.caption)
                }
                .buttonStyle(ButtonStyleGreen())

                Button {
                    rejectSuggestion()
                } label: {
                    Text("Keep Original")
                        .font(.caption)
                }
                .buttonStyle(ButtonStyleRed())
            }
        }
        .padding(12)
        .frame(width: 250)
        .background(.white)
        .cornerRadius(8)
    }

    private func optionsView(category: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button { [weak overlayStateModel] in
                    overlayStateModel?.actionToolState = .category
                } label: {
                    Image(systemName: "arrow.backward")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Text(category)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            if suggestionTypes.count > 0 {
                ForEach(suggestionTypes.filter { $0.model.category == category }, id: \.model.typeKey) { suggestionType in
                    Button { [weak overlayStateModel] in
                        guard !isProcessing else { return }
                        isProcessing = true
                        overlayStateModel?.actionToolState = .loading

                        Task { @MainActor in
                            await processSuggestion(suggestionType: suggestionType)
                        }
                    } label: {
                        HStack(spacing: .zero) {
                            Text(suggestionType.displayName)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    overlayStateModel.actionToolState = .idle
                } label: {
                    Text("Close suggestions")
                        .font(.caption)
                }
                .buttonStyle(ButtonStyleRed())
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            } else {
                Text("No suggestions enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(minWidth: 150)
        .frame(minHeight: 50)
        .background(.white)
        .cornerRadius(8)
    }

    private var categoryView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Categories")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            if suggestionCategories.count > 0 {
                ForEach(suggestionCategories, id: \.self) { suggestionCategoryName in
                    Button { [weak overlayStateModel] in
                        overlayStateModel?.actionToolState = .options(suggestionCategoryName)
                    } label: {
                        HStack {
                            Text(suggestionCategoryName)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No suggestions enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                overlayStateModel.actionToolState = .idle
            } label: {
                Text("Close suggestions")
                    .font(.caption)
            }
            .buttonStyle(ButtonStyleRed())
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
        .padding(12)
        .frame(minWidth: 150)
        .frame(minHeight: 50)
        .background(.white)
        .cornerRadius(8)
    }

    // MARK: - State Management

    private func handleStateChange(from oldState: ActionToolState, to newState: ActionToolState) {
        let wasInteractive = isInteractiveState(oldState)
        let isNowInteractive = isInteractiveState(newState)

        if !wasInteractive && isNowInteractive {
            // Entering interactive state - pause monitoring to preserve element info
            accessibilityManager.pauseForInteraction()
            injectionError = nil
            Analytics.trackAsync(.actionMenuOpened)
        } else if wasInteractive && !isNowInteractive {
            // Leaving interactive state - resume monitoring
            accessibilityManager.resumeFromInteraction()
            Analytics.trackAsync(.actionMenuClosed)
        }
    }

    private func isInteractiveState(_ state: ActionToolState) -> Bool {
        switch state {
        case .idle:
            return false
        case .loading, .action, .options, .category:
            return true
        }
    }

    private func resetState() {
        injectionError = nil
        accessibilityManager.resumeFromInteraction()
        overlayStateModel.actionToolState = .idle
    }

    // MARK: - Suggestion Processing

    @MainActor
    private func processSuggestion(suggestionType: SuggestionType) async {
        defer { isProcessing = false }

        let suggestionTypeKey = suggestionType.model.typeKey
        let suggestionCategory = suggestionType.model.category
        let startTime = Date()

        // Track suggestion type selected and processing started
        Analytics.trackAsync(.suggestionTypeSelected(type: suggestionTypeKey, category: suggestionCategory))
        Analytics.trackAsync(.suggestionProcessingStarted(type: suggestionTypeKey))

        do {
            let result = try await suggestionDomainService
                .process(
                    text: overlayStateModel.elementInfo?.text ?? "",
                    suggestionGroupId: profileDomainService.currentProfile.model.defaultSuggestionGroupId,
                    teamId: profileDomainService.currentProfile.model.defaultTeamId,
                    suggestionType: suggestionTypeKey,
                    application: overlayStateModel.elementInfo?.applicationName ?? "n/a"
                )

            try Task.checkCancellation()

            let duration = Date().timeIntervalSince(startTime)
            Analytics.trackAsync(.suggestionProcessingCompleted(type: suggestionTypeKey, duration: duration))

            actionText = result.model.suggestedText
            overlayStateModel.actionToolState = .action
        } catch is CancellationError {
            logger.debug("LLM processing was cancelled")
            Analytics.trackAsync(.suggestionProcessingFailed(type: suggestionTypeKey, error: "cancelled"))
            resetState()
        } catch {
            logger.debug("Error processing LLM request: \(error)")
            Analytics.trackAsync(.suggestionProcessingFailed(type: suggestionTypeKey, error: error.localizedDescription))
            resetState()
        }
    }

    // MARK: - Text Injection

    @MainActor
    private func replaceText() async {
        logger.debug("Starting text replacement")
        injectionError = nil

        // Get the preserved element info
        let targetInfo = overlayStateModel.elementInfo
        let applicationName = targetInfo?.applicationName ?? "unknown"

        guard targetInfo != nil else {
            logger.debug("No element info available")
            injectionError = "Target field not found"
            Analytics.trackAsync(.textInjectionFailed(application: applicationName, error: "no_element_info"))
            return
        }

        // Track injection started
        Analytics.trackAsync(.textInjectionStarted(application: applicationName))

        do {
            // Use the new injection service which gets a fresh element reference
            try textInjectionService.injectText(actionText, targetInfo: targetInfo)
            logger.debug("Text injection successful")

            // Track success and suggestion accepted
            Analytics.trackAsync(.textInjectionSucceeded(application: applicationName, method: "injection_service"))
            Analytics.trackAsync(.suggestionAccepted(type: "text_replacement"))

            resetState()
        } catch let error as AccessibilityError {
            logger.debug("Accessibility error: \(error.localizedDescription)")
            injectionError = error.localizedDescription
            Analytics.trackAsync(.textInjectionFailed(application: applicationName, error: error.localizedDescription))
        } catch {
            logger.debug("Unexpected error: \(error.localizedDescription)")
            injectionError = "Failed to update text"
            Analytics.trackAsync(.textInjectionFailed(application: applicationName, error: error.localizedDescription))
        }
    }

    private func rejectSuggestion() {
        Analytics.trackAsync(.suggestionRejected(type: "text_replacement"))
        resetState()
    }
}
