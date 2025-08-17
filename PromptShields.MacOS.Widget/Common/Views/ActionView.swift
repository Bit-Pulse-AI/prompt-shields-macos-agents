import SwiftUI

struct ActionView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    
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
                        Button {
                            overlayStateModel.actionToolState = .loading
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                overlayStateModel.actionToolState = .idle
                            }
                        } label: {
                            Text("Enhance privacy and security")
                        }
                        Button {
                            overlayStateModel.actionToolState = .loading
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                overlayStateModel.actionToolState = .idle
                            }
                        } label: {
                            Text("Enhance prompt")
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
