import SwiftUI
import Combine
import SwiftData

final class OverlayStateModel: ObservableObject {
    @Published var elementInfo: ElementInfo?
    @Published var isLoadingFromLLM: Bool = false
    @Published var promptText: String = ""
    @Published var textFieldHeight: CGFloat = 40
}

// swiftlint:disable:next type_name
@main
struct MainApp: App {
    enum Field: Hashable {
        case textField
    }
    
    // MARK: - Properties
    @StateObject private var overlayStateModel = OverlayStateModel()
    @Environment(\.openWindow) private var openWindow
    /// Application delegate for handling app lifecycle events
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    static let overlayRender = "overlay-render"
    static let actionRender = "action-render"
    
    var body: some Scene {
        WindowGroup("Main", id: "main-window") {
            MainView(overlayStateObject: _overlayStateModel)
                .onAppear {
                    configureAppAppearance()
                }
        }
        .windowStyle(.hiddenTitleBar)
        
        Window("Overlay Render", id: MainApp.overlayRender) {
            OverlayView()
        }
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)
        Window("Action", id: MainApp.actionRender) {
            ZStack(alignment: .leading) {
                if overlayStateModel.isLoadingFromLLM {
                    VStack {
                        HStack {
                            Button {
                            } label: {
                                Text("Enhance privacy and security")
                            }
                            Button {
                            } label: {
                                Text("Enhance prompt")
                            }
                        }
                        ExpandingTextEditor(text: $overlayStateModel.promptText, height: $overlayStateModel.textFieldHeight)
                    }
                    .padding()
                    .background(.white)
                    .cornerRadius(8)
                } else {
                    Button {
                        overlayStateModel.isLoadingFromLLM = true
                    } label: {
                        Image(ImageResource(name: "logo_mid", bundle: .main))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                    .buttonStyle(ButtonStyleWhite())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .environmentObject(overlayStateModel)
        .windowStyle(.hiddenTitleBar)
    }
    
    /// Configures the application appearance settings
    private func configureAppAppearance() {
        openWindow(id: "overlay-render")
        openWindow(id: "action-render")
        NSApp.appearance = NSAppearance(named: .aqua)
    }
}
