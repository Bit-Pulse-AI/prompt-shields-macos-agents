import SwiftUI
import os

struct ActionView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
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

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ActionView.self)
    )

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
                    HStack {
                        Button {
                                Task {
                                    guard let elementIdentifier = overlayStateModel.elementInfo?.elementIdentifier else {
                                        return
                                    }
                                    await replaceText(axElementID: elementIdentifier)
                                }
                        } label: {
                            Text("Agree & Update")
                        }
                        .buttonStyle(ButtonStyleGreen())
                        Button {
                            overlayStateModel.actionToolState = .idle
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
                                        do {
                                            let result = try await suggestionDomainService
                                                .process(
                                                    text:
                                                        overlayStateModel?.elementInfo?.text ?? "",
                                                        llmProvider: LLMProvider
                                                                        .AZURE_PROMPTSHIELDS
                                                                        .rawValue,
                                                    suggestionGroupId: profileDomainService.currentProfile.model.defaultSuggestionGroupId,
                                                    teamId: profileDomainService.currentProfile.model.defaultTeamId,
                                                        suggestionType: suggestionType.model.suggestionType,
                                                        application: overlayStateModel?.elementInfo?.applicationName ?? "n/a")

                                            try Task.checkCancellation()

                                            if let axUIElement = overlayStateModel?.elementInfo?.element {
                                                if await isValidAXUIElement(axUIElement) {
                                                    await MainActor.run {
                                                        actionText = result.model.suggestedText
                                                        overlayStateModel?.actionToolState = .action
                                                    }
                                                } else {
                                                    logger.error("AXUIElement is no longer valid")
                                                    await MainActor.run {
                                                        overlayStateModel?.actionToolState = .idle
                                                    }
                                                }
                                            }
                                        } catch is CancellationError {
                                            logger.warning("LLM processing was cancelled")
                                            await MainActor.run {
                                                overlayStateModel?.actionToolState = .idle
                                            }
                                        } catch {
                                            logger.error("Error processing LLM request: \(error)")
                                            await MainActor.run {
                                                overlayStateModel?.actionToolState = .idle
                                            }
                                        }
                                        await MainActor.run {
                                            isProcessing = false
                                        }
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
            // Cancel any ongoing processing
            isProcessing = false
        }
    }

    func replaceText(axElementID: AXElementID) async {
        if await isValidAXUIElement(axUIElement) {
            Task {
                do {
                    // Use the isSelectedText information from the element info
                    let isSelectedText = overlayStateModel.elementInfo?.isSelectedText ?? false
                    try await TextInjector.shared.injectText(actionText, into: axUIElement, isSelectedText: isSelectedText)
                    await MainActor.run {
                        self.overlayStateModel.actionToolState = .idle
                    }
                } catch {
                    logger.error("Error injecting text: \(error)")
                    await MainActor.run {
                        self.overlayStateModel.actionToolState = .idle
                    }
                }
            }
        }
    }

    private func isValidAXUIElement(_ element: AXUIElement) async -> Bool {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(element, &pid)
        guard result == .success else {
            return false
        }
        let app = NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
        return app != nil
    }
}
