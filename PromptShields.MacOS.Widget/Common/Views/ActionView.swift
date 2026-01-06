import SwiftUI
import os

struct ActionView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @Environment(\.suggestionDomainService) private var suggestionDomainService
    @Environment(\.profileDomainService) private var profileDomainService

    @StateObject private var suggestionTypesQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.suggestionName, order: .reverse)],
        mapping: DefaultMapping<SuggestionType>.self
    )
    @StateObject private var userPreferencesTypesQueryable = ObservableQueryable(
        mapping: DefaultMapping<UserPreferences>.self
    )
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
        let enabledFilters = userPreferences?.model.enabledSuggestionTypes ?? []
        return suggestionTypesQueryable.wrappedValue.filter {
            enabledFilters.contains($0.model.suggestionType)
        }.sorted(by: {
            $0.model.suggestionName < $1.model.suggestionName
        })
    }

    private var suggestionCategories: [String] {
        let set = suggestionTypes.compactMap {
            $0.model.suggestionTypeCategory
        }
        return Array(Set(set)).sorted(by: {
            $0 < $1
        })
    }

    private var userPreferences: UserPreferences? {
        userPreferencesTypesQueryable.wrappedValue.first
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
            overlayStateModel.actionToolState = .category
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
                    Task {
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
                ForEach(suggestionTypes.filter { $0.model.suggestionTypeCategory == category }, id: \.model.suggestionType) { suggestionType in
                    Button { [weak overlayStateModel] in
                        guard !isProcessing else { return }
                        isProcessing = true
                        overlayStateModel?.actionToolState = .loading

                        Task {
                            await processSuggestion(suggestionType: suggestionType)
                        }
                    } label: {
                        Text(suggestionType.model.suggestionName)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                    .padding(.vertical, 2)
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
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)
                    .padding(.vertical, 2)
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

        let suggestionTypeName = suggestionType.model.suggestionType
        let suggestionCategory = suggestionType.model.suggestionTypeCategory
        let startTime = Date()

        // Track suggestion type selected and processing started
        Analytics.trackAsync(.suggestionTypeSelected(type: suggestionTypeName, category: suggestionCategory))
        Analytics.trackAsync(.suggestionProcessingStarted(type: suggestionTypeName))

        do {
            let result = try await suggestionDomainService
                .process(
                    text: overlayStateModel.elementInfo?.text ?? "",
                    llmProvider: LLMProvider.AZURE_PROMPTSHIELDS.rawValue,
                    suggestionGroupId: profileDomainService.currentProfile.model.defaultSuggestionGroupId,
                    teamId: profileDomainService.currentProfile.model.defaultTeamId,
                    suggestionType: suggestionTypeName,
                    application: overlayStateModel.elementInfo?.applicationName ?? "n/a"
                )

            try Task.checkCancellation()

            let duration = Date().timeIntervalSince(startTime)
            Analytics.trackAsync(.suggestionProcessingCompleted(type: suggestionTypeName, duration: duration))

            actionText = result.model.suggestedText
            overlayStateModel.actionToolState = .action
        } catch is CancellationError {
            logger.debug("LLM processing was cancelled")
            Analytics.trackAsync(.suggestionProcessingFailed(type: suggestionTypeName, error: "cancelled"))
            resetState()
        } catch {
            logger.debug("Error processing LLM request: \(error)")
            Analytics.trackAsync(.suggestionProcessingFailed(type: suggestionTypeName, error: error.localizedDescription))
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
