import Foundation

/// 原生 HTTP 客户端 (绕 WKWebView 的 CORS, 可设 Origin/Referer 等 fetch 禁用头)。
/// JS 经 Native.httpReq(reqId, method, url, headersJson, body) 调用, 结果异步经
/// window.__httpCb(reqId, {status, ctype, text}) 回灌 — 与安卓 HttpBridge.java 同回包格式。
enum HttpBridge {
    typealias Callback = (_ reqId: String, _ resultJson: String) -> Void

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    static func exec(reqId: String, method: String, url: String, headersJson: String,
                     body: String, b64: Bool, cb: @escaping Callback) {
        guard let u = URL(string: url) else {
            cb(reqId, "{\"status\":0,\"error\":\"bad url\"}")
            return
        }
        var req = URLRequest(url: u)
        let m = method.isEmpty ? "GET" : method.uppercased()
        req.httpMethod = m
        if let hd = headersJson.data(using: .utf8),
           let headers = (try? JSONSerialization.jsonObject(with: hd)) as? [String: Any] {
            for (k, v) in headers { req.setValue("\(v)", forHTTPHeaderField: k) }
        }
        if !body.isEmpty && m != "GET" && m != "HEAD" {
            req.httpBody = body.data(using: .utf8)
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        }
        session.dataTask(with: req) { data, resp, err in
            if let err = err {
                cb(reqId, "{\"status\":0,\"error\":\(jsonStr(err.localizedDescription))}")
                return
            }
            let http = resp as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            let ctype = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
            let d = data ?? Data()
            if b64 {
                let payload = d.base64EncodedString()
                cb(reqId, "{\"status\":\(code),\"ctype\":\(jsonStr(ctype)),\"b64\":\(jsonStr(payload)),\"size\":\(d.count)}")
            } else {
                let text = String(data: d, encoding: .utf8) ?? ""
                cb(reqId, "{\"status\":\(code),\"ctype\":\(jsonStr(ctype)),\"text\":\(jsonStr(text))}")
            }
        }.resume()
    }

    static func jsonStr(_ s: String) -> String {
        if let d = try? JSONSerialization.data(withJSONObject: [s]),
           let arr = String(data: d, encoding: .utf8), arr.count >= 2 {
            return String(arr.dropFirst().dropLast())
        }
        return "\"\""
    }
}
