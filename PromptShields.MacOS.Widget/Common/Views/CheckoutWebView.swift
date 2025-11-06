import SwiftUI
import WebKit

struct CheckoutWebView: NSViewRepresentable {
    let url: URL
    let onFinished: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = "PromptShieldsCheckout/1.0"
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onFinished: (Bool) -> Void

        init(onFinished: @escaping (Bool) -> Void) {
            self.onFinished = onFinished
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if let urlString = navigationAction.request.url?.absoluteString {
                if urlString.hasPrefix(webBillingSuccessURL) {
                    onFinished(true)
                    decisionHandler(.cancel)
                    return
                }
                if urlString.hasPrefix(webBillingCancelURL) {
                    onFinished(false)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        // Handle target=_blank by loading into the same webView
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
