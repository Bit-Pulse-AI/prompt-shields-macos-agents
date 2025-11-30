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
        ZStack(alignment: .leading) {
            switch overlayStateModel.actionToolState {
            case .idle:
                Button {
                    overlayStateModel.actionToolState = .category
                } label: {
                    Image(ImageResource(name: "logo_mid", bundle: .main))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .buttonStyle(ButtonStyleWhite())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading:
                VStack {
                    ProgressView()
                        .controlSize(.small)
                }
                .padding()
                .background(.white)
                .cornerRadius(8)
            case .action:
                VStack {
                    ScrollView {
                        Text(actionText)
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                    }

                    if let error = injectionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.vertical, 4)
                    }

                    HStack {
                        Button {
                            Task {
                                await replaceText()
                            }
                        } label: {
                            Text("Agree & Update")
                        }
                        .buttonStyle(ButtonStyleGreen())
                        Button {
                            resetState()
                        } label: {
                            Text("Keep Original")
                        }
                        .buttonStyle(ButtonStyleRed())
                    }
                }
                .padding()
                .background(.white)
                .cornerRadius(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .options(let category):
                VStack {
                    HStack(spacing: .zero) {
                        Button { [weak overlayStateModel] in
                            overlayStateModel?.actionToolState = .category
                        } label: {
                            Image(systemName: "arrow.backward")
                                .frame(width: 12, height: 12)
                        }.buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading) {
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
                                }
                                .disabled(isProcessing)
                            }
                        } else {
                            Text("No suggestions enabled")
                        }
                    }
                }
                .padding()
                .background(.white)
                .cornerRadius(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .category:
                VStack {
                    VStack(alignment: .leading) {
                        if suggestionCategories.count > 0 {
                            ForEach(suggestionCategories, id: \.self) { suggestionCategoryName in
                                Button { [weak overlayStateModel] in
                                    overlayStateModel?.actionToolState = .options(suggestionCategoryName)
                                } label: {
                                    Text(suggestionCategoryName)
                                }
                                .disabled(isProcessing)
                            }
                        } else {
                            Text("No suggestions enabled")
                        }
                    }
                }
                .padding()
                .background(.white)
                .cornerRadius(8)
            }
        }
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

    // MARK: - State Management

    private func handleStateChange(from oldState: ActionToolState, to newState: ActionToolState) {
        let wasInteractive = isInteractiveState(oldState)
        let isNowInteractive = isInteractiveState(newState)

        if !wasInteractive && isNowInteractive {
            // Entering interactive state - pause monitoring to preserve element info
            accessibilityManager.pauseForInteraction()
            injectionError = nil
        } else if wasInteractive && !isNowInteractive {
            // Leaving interactive state - resume monitoring
            accessibilityManager.resumeFromInteraction()
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

        do {
            let result = try await suggestionDomainService
                .process(
                    text: overlayStateModel.elementInfo?.text ?? "",
                    llmProvider: LLMProvider.AZURE_PROMPTSHIELDS.rawValue,
                    suggestionGroupId: profileDomainService.currentProfile.model.defaultSuggestionGroupId,
                    teamId: profileDomainService.currentProfile.model.defaultTeamId,
                    suggestionType: suggestionType.model.suggestionType,
                    application: overlayStateModel.elementInfo?.applicationName ?? "n/a"
                )

            try Task.checkCancellation()

            actionText = result.model.suggestedText
            overlayStateModel.actionToolState = .action
        } catch is CancellationError {
            logger.warning("LLM processing was cancelled")
            resetState()
        } catch {
            logger.error("Error processing LLM request: \(error)")
            resetState()
        }
    }

    // MARK: - Text Injection

    @MainActor
    private func replaceText() async {
        logger.info("Starting text replacement")
        injectionError = nil

        // Get the preserved element info
        let targetInfo = overlayStateModel.elementInfo

        guard targetInfo != nil else {
            logger.error("No element info available")
            injectionError = "Target field not found"
            return
        }

        do {
            // Use the new injection service which gets a fresh element reference
            try textInjectionService.injectText(actionText, targetInfo: targetInfo)
            logger.info("Text injection successful")
            resetState()
        } catch let error as AccessibilityError {
            logger.error("Accessibility error: \(error.localizedDescription)")
            injectionError = error.localizedDescription
        } catch {
            logger.error("Unexpected error: \(error.localizedDescription)")
            injectionError = "Failed to update text"
        }
    }
}
