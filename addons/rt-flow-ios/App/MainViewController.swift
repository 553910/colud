import UIKit
import WebKit

/// 主面板 — 首屏切号 switch.html (与安卓首启 newTab(SWITCH) 同序),
/// 底部原生导航栏在 切号/道盘/隧道/云盘 面板间切换 (对齐安卓菜单 SWITCH/CLOUD/TUNNEL)。
final class MainViewController: UIViewController {
    private var webView: WKWebView!
    private var bridge: NativeBridge!
    private var seg: UISegmentedControl!

    private static let panels: [(title: String, page: String)] = [
        ("切号", "switch.html"),
        ("道盘", "daopan.html"),
        ("隧道", "tunnel.html"),
        ("云盘", "cloud.html"),
    ]

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

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        bridge = NativeBridge(webView: webView)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        view.addSubview(webView)

        seg = UISegmentedControl(items: Self.panels.map { $0.title })
        seg.selectedSegmentIndex = 0
        seg.backgroundColor = UIColor(white: 0.08, alpha: 1)
        seg.selectedSegmentTintColor = UIColor(white: 0.25, alpha: 1)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.lightGray], for: .normal)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        seg.addTarget(self, action: #selector(panelChanged), for: .valueChanged)
        view.addSubview(seg)

        webView.translatesAutoresizingMaskIntoConstraints = false
        seg.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: seg.topAnchor, constant: -4),
            seg.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            seg.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            seg.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -2),
            seg.heightAnchor.constraint(equalToConstant: 34),
        ])

        loadPanel(0) // 首屏切号 (对齐安卓: restoreTabs 失败即 newTab(SWITCH))
    }

    private func loadPanel(_ i: Int) {
        let page = Self.panels[i].page
        webView.load(URLRequest(url: URL(string: "rtflow://engine/\(page)")!))
    }

    @objc private func panelChanged() {
        loadPanel(seg.selectedSegmentIndex)
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
