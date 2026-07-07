import WebKit

/// 常驻中继引擎 — 隐藏 WKWebView 加载 engine.html (relay-app.js 出站 WSS 连中继),
/// 与安卓 RelayService 的隐藏引擎 WebView 等价。iOS 无前台服务, App 在前台期间常驻;
/// 退后台由系统暂停, 回前台自动续连 (relay-app.js 自带断线重连/半开死链判定)。
final class EngineController: NSObject {
    static let shared = EngineController()

    private(set) var webView: WKWebView?
    private var bridge: NativeBridge?
    var lastStatus = "{}"

    func start() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AssetSchemeHandler(), forURLScheme: AssetSchemeHandler.scheme)
        if let shim = Bundle.main.url(forResource: "native-shim", withExtension: "js"),
           let src = try? String(contentsOf: shim, encoding: .utf8) {
            config.userContentController.addUserScript(
                WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isHidden = true
        bridge = NativeBridge(webView: wv)
        wv.uiDelegate = self
        // 挂到 window 上保持存活 (不挂视图树的 WKWebView 可能被暂停)
        DispatchQueue.main.async {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            scene?.windows.first?.addSubview(wv)
        }
        wv.load(URLRequest(url: URL(string: "rtflow://engine/engine.html")!))
        webView = wv
    }

    func reloadEngine() {
        DispatchQueue.main.async { self.webView?.reload() }
    }
}

extension EngineController: WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        if prompt == NativeBridge.promptToken, let bridge = bridge {
            completionHandler(bridge.handle(defaultText ?? ""))
        } else {
            completionHandler(nil)
        }
    }
}
