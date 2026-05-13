import SwiftUI
@preconcurrency import WebKit

struct WebTabView: UIViewRepresentable {
    let tab: TabModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        // Чтобы во время load'а не вспыхивал стандартный белый WebKit-bg
        // на тёмной shell-палитре.
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.043, green: 0.043, blue: 0.059, alpha: 1)
        webView.scrollView.backgroundColor = .clear
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.tab = tab
        if let url = tab.currentURL, webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var tab: TabModel
        weak var webView: WKWebView?

        init(tab: TabModel) {
            self.tab = tab
        }

        func webView(_ webView: WKWebView,
                     didStartProvisionalNavigation navigation: WKNavigation!) {
            tab.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            tab.isLoading = false
            tab.pageTitle = webView.title ?? ""
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
            if let url = webView.url, url != tab.currentURL {
                tab.mode = .web(url)
                tab.addressInput = url.absoluteString
            }
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            tab.isLoading = false
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            tab.isLoading = false
        }
    }
}
