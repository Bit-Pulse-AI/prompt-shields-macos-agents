import SwiftUI

struct ActionView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    @Environment(\.llmDomainService) private var llmDomainService
    
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
                        ForEach(SuggestionType.allCases, id: \.self) { type in
                            Button {
                                overlayStateModel.actionToolState = .loading
                                Task {
                                    do {
                                        let result = try await llmDomainService.process(text: overlayStateModel.elementInfo?.text ?? "", llmProvider: .AZURE_PROMPTSHIELDS, suggestionType: type, application: overlayStateModel.elementInfo?.applicationName ?? "n/a")
                                        if let axUIElement = overlayStateModel.elementInfo?.element {
                                            Task {
                                                do {
                                                    try await TextInjector().injectText(result, into: axUIElement)
                                                } catch {
                                                    print("Error \(error)")
                                                }
                                            }
                                        }
                                        overlayStateModel.actionToolState = .idle
                                    } catch {
                                        print("Error \(error)")
                                    }
                                }
                            } label: {
                                Text(type.displayName)
                            }
                        }
                    }
                }
                .padding()
                .background(.white)
                .cornerRadius(8)
            }
//            if overlayStateModel.isLoadingFromLLM {
//
//            } else {
//
//            }
        }
    }
}
