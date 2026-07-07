import WebKit

/// rtflow://engine/<path> → App Bundle 里的 engine/ 资产 (与安卓 file:///android_asset/engine 等价)。
/// 用自定义 scheme 而非 file:// 是为了给页面一个稳定 origin (localStorage/同源 XHR 可用)。
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "rtflow"

    private static let mimeTypes: [String: String] = [
        "html": "text/html", "js": "application/javascript", "css": "text/css",
        "json": "application/json", "png": "image/png", "jpg": "image/jpeg",
        "svg": "image/svg+xml", "ico": "image/x-icon", "woff2": "font/woff2",
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "daopan.html" }

        guard let fileURL = Bundle.main.url(forResource: path, withExtension: nil, subdirectory: "engine"),
              let data = try? Data(contentsOf: fileURL) else {
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!
            urlSchemeTask.didReceive(resp)
            urlSchemeTask.didFinish()
            return
        }
        let ext = (path as NSString).pathExtension.lowercased()
        let mime = Self.mimeTypes[ext] ?? "application/octet-stream"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime + "; charset=utf-8",
                                                  "Cache-Control": "no-cache"])!
        urlSchemeTask.didReceive(resp)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
