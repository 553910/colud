import UIKit
import WebKit

/// 主面板 — WKWebView 加载 daopan.html (与安卓主壳 DP_URL 同页),
/// 面板内导航 switch.html / tunnel.html / cloud.html 等均在本 webview 内。
final class MainViewController: UIViewController {
    private var webView: WKWebView!
    private var bridge: NativeBridge!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Devin Cloud"
        navigationController?.setNavigationBarHidden(true, animated: false)
        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: AssetSchemeHandler.scheme)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        if let shim = Bundle.main.url(forResource: "native-shim", withExtension: "js"),
           let src = try? String(contentsOf: shim, encoding: .utf8) {
            config.userContentController.addUserScript(
                WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        bridge = NativeBridge(webView: webView)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        view.addSubview(webView)

        webView.load(URLRequest(url: URL(string: "rtflow://engine/daopan.html")!))
    }
}

extension MainViewController: WKUIDelegate, WKNavigationDelegate {
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        if prompt == NativeBridge.promptToken {
            completionHandler(bridge.handle(defaultText ?? ""))
            return
        }
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    // 外链 (http/https 非 devin 域) → 系统浏览器; app.devin.ai → 账号标签
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        if url.scheme == AssetSchemeHandler.scheme { decisionHandler(.allow); return }
        if url.scheme == "http" || url.scheme == "https" {
            if url.host == "app.devin.ai" {
                TabManager.shared.openTab(url: url.absoluteString, accountJson: "{}")
            } else {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
