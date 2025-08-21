import SwiftUI

struct ActionView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    @Environment(\.llmDomainService) private var llmDomainService
    
    // Track processing state to prevent multiple simultaneous requests
    @State private var isProcessing = false
    
    // Cache suggestion types to avoid repeated allCases calls
    private let suggestionTypes = SuggestionType.allCases
    
    // Track if view is active to prevent memory leaks
    @State private var isViewActive = true
    
    // Cache display names to avoid repeated computation
    private var suggestionTypeDisplayNames: [SuggestionType: String] {
        Dictionary(uniqueKeysWithValues: suggestionTypes.map { ($0, $0.displayName) })
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
                        ForEach(suggestionTypes, id: \.self) { type in
                            Button { [weak overlayStateModel] in
                                guard !isProcessing else { return }
                                isProcessing = true
                                overlayStateModel?.actionToolState = .loading
                                
                                Task {
                                    do {
                                        let result = try await llmDomainService.process(text: overlayStateModel?.elementInfo?.text ?? "", llmProvider: .AZURE_PROMPTSHIELDS, suggestionType: type, application: overlayStateModel?.elementInfo?.applicationName ?? "n/a")
                                        
                                        // Check for cancellation before proceeding
                                        try Task.checkCancellation()
                                        
                                        if let axUIElement = overlayStateModel?.elementInfo?.element {
                                            // Validate the element before using it
                                            if await isValidAXUIElement(axUIElement) {
                                                Task { [weak axUIElement] in
                                                    guard let axUIElement else {
                                                        return
                                                    }
                                                    do {
                                                        try await TextInjector.shared.injectText(result, into: axUIElement)
                                                    } catch {
                                                        print("Error injecting text: \(error)")
                                                    }
                                                }
                                            } else {
                                                print("AXUIElement is no longer valid")
                                            }
                                        }
                                        
                                        overlayStateModel?.actionToolState = .idle
                                    } catch is CancellationError {
                                        print("LLM processing was cancelled")
                                        overlayStateModel?.actionToolState = .idle
                                    } catch {
                                        print("Error processing LLM request: \(error)")
                                        overlayStateModel?.actionToolState = .idle
                                    }
                                
                                    isProcessing = false
                                }
                            } label: {
                                Text(suggestionTypeDisplayNames[type] ?? type.displayName)
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
