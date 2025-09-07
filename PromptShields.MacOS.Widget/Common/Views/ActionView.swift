import SwiftUI
import os

struct ActionView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    @Environment(\.suggestionDomainService) private var suggestionDomainService
    @Environment(\.profileDomainService) private var profileDomainService
    @Environment(\.userPreferencesDomainService) private var userPreferencesDomainService
    @StateObject private var suggestionTypesQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.suggestionName, order: .reverse)],
        mapping: DefaultMapping<SuggestionType>.self
    )
    @StateObject private var userPreferencesTypesQueryable = ObservableQueryable(
        mapping: DefaultMapping<UserPreferences>.self
    )
    @State private var isProcessing = false
    @State private var isViewActive = true
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ActionView.self)
    )
    
    private var suggestionTypes: [SuggestionType] {
        let enabledFilters = userPreferences?.model.enabledSuggestionTypes ?? []
        return suggestionTypesQueryable.wrappedValue.filter {
            enabledFilters.contains($0.model.suggestionType)
        }
    }
    
    private var userPreferences: UserPreferences? {
        userPreferencesTypesQueryable.wrappedValue.first
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            switch overlayStateModel.actionToolState {
            case .idle:
                Button {
                    overlayStateModel.actionToolState = .options
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
            case .options:
                VStack {
                    VStack(alignment: .leading) {
                        ForEach(suggestionTypes, id: \.model.suggestionType) { suggestionType in
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
                                                    suggestionType: suggestionType.model.suggestionType,
                                                    application: overlayStateModel?.elementInfo?.applicationName ?? "n/a")

                                        try Task.checkCancellation()
                                        
                                        if let axUIElement = overlayStateModel?.elementInfo?.element {
                                            if await isValidAXUIElement(axUIElement) {
                                                Task { [weak axUIElement] in
                                                    guard let axUIElement else {
                                                        return
                                                    }
                                                    do {
                                                        try await TextInjector.shared.injectText(result.model.suggestedText, into: axUIElement)
                                                    } catch {
                                                        logger.error("Error injecting text: \(error)")
                                                    }
                                                }
                                            } else {
                                                logger.error("AXUIElement is no longer valid")
                                            }
                                        }
                                        overlayStateModel?.actionToolState = .idle
                                    } catch is CancellationError {
                                        logger.warning("LLM processing was cancelled")
                                        overlayStateModel?.actionToolState = .idle
                                    } catch {
                                        logger.error("Error processing LLM request: \(error)")
                                        overlayStateModel?.actionToolState = .idle
                                    }
                                    isProcessing = false
                                }
                            } label: {
                                Text(suggestionType.model.suggestionName)
                            }
                            .disabled(isProcessing)
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
