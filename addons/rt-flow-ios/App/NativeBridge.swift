import UIKit
import WebKit
import UserNotifications

/// window.Native 的 iOS 原生实现 — 与安卓 RelayService.Bridge / MainActivity 的
/// @JavascriptInterface 面同名同语义。JS 侧经 native-shim.js 的同步 prompt 桥调入:
///   prompt("__dao_native__", JSON{m,a}) → dispatch(m,a) → JSON{r} 同步返回。
/// 异步方法 (httpReq/httpReqB64) 立即返回, 结果经 evaluateJavaScript 回灌 window.__httpCb。
final class NativeBridge {
    static let promptToken = "__dao_native__"
    static let devinHome = "https://app.devin.ai/"

    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    // ── 存储路径 (对齐安卓: Documents/{user,vault,DevinCloud/backups}) ──
    private static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private static func dir(_ parts: String...) -> URL {
        var u = docs
        for p in parts { u.appendPathComponent(p) }
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private static func safe(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
    }
    private static func readText(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    private static func writeText(_ url: URL, _ s: String) {
        try? s.data(using: .utf8)?.write(to: url)
    }

    static func readUserFile(_ name: String) -> String { readText(dir("user").appendingPathComponent(safe(name))) }
    static func writeUserFile(_ name: String, _ content: String) { writeText(dir("user").appendingPathComponent(safe(name)), content) }
    private static func bkDir(_ folder: String) -> URL { dir("DevinCloud", "backups", safe(folder)) }

    // ── 同步桥入口: JSON{m,a} → JSON{r} ──
    func handle(_ payload: String) -> String {
        guard let d = payload.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let m = obj["m"] as? String else { return "{\"r\":null}" }
        let a = obj["a"] as? [Any] ?? []
        let r = dispatch(m, a)
        if let data = try? JSONSerialization.data(withJSONObject: ["r": r ?? NSNull()]),
           let s = String(data: data, encoding: .utf8) { return s }
        return "{\"r\":null}"
    }

    private func argStr(_ a: [Any], _ i: Int) -> String {
        guard i < a.count else { return "" }
        if let s = a[i] as? String { return s }
        if a[i] is NSNull { return "" }
        return "\(a[i])"
    }
    private func argBool(_ a: [Any], _ i: Int) -> Bool {
        guard i < a.count else { return false }
        if let b = a[i] as? Bool { return b }
        if let n = a[i] as? NSNumber { return n.boolValue }
        return (a[i] as? String) == "true"
    }
    private func argInt(_ a: [Any], _ i: Int) -> Int {
        guard i < a.count else { return 0 }
        if let n = a[i] as? NSNumber { return n.intValue }
        return Int(argStr(a, i)) ?? 0
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func dispatch(_ m: String, _ a: [Any]) -> Any? {
        switch m {
        // ── 应用 ──
        case "appVer":
            return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        case "log":
            NSLog("RTFlowEngine %@", argStr(a, 0)); return nil
        case "toast", "notify":
            Self.showToast(argStr(a, 0)); return nil
        case "notifyGlobal":
            Self.postNotification(title: argStr(a, 1), text: argStr(a, 2)); return nil
        case "vibrate":
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(); return nil
        case "appToFront":
            return true
        case "keepAliveStatus":
            return "{\"foregroundService\":true,\"batteryOptExempt\":true,\"overlay\":false}"
        case "netInfo":
            return "{\"metered\":false,\"online\":true}"
        case "reload", "relayRestart":
            EngineController.shared.reloadEngine(); return nil

        // ── 中继配置 (动态优先, 内置 conn.json 兜底) ──
        case "getConn", "conn":
            let dyn = Self.readUserFile("relay-config.json")
            if dyn.count > 5 { return dyn }
            if let u = Bundle.main.url(forResource: "conn.json", withExtension: nil, subdirectory: "engine") {
                return Self.readText(u)
            }
            return "{}"
        case "saveRelayConfig":
            Self.writeUserFile("relay-config.json", argStr(a, 0))
            EngineController.shared.reloadEngine()
            return true
        case "onStatus":
            EngineController.shared.lastStatus = argStr(a, 0); return nil
        case "relayStatus", "status":
            return EngineController.shared.lastStatus
        case "restart":
            EngineController.shared.reloadEngine(); return nil

        // ── 文件 / vault / 备份库 ──
        case "writeFile":
            Self.writeUserFile(argStr(a, 0), argStr(a, 1)); return nil
        case "readFile":
            return Self.readUserFile(argStr(a, 0))
        case "vaultSave":
            let k = argStr(a, 0)
            if !k.isEmpty { Self.writeText(Self.dir("vault").appendingPathComponent(Self.safe(k) + ".json"), argStr(a, 1)) }
            return nil
        case "vaultLoad":
            return Self.readText(Self.dir("vault").appendingPathComponent(Self.safe(argStr(a, 0)) + ".json"))
        case "vaultListBackupAccounts":
            let base = Self.dir("DevinCloud", "backups")
            let names = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey]))?
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map { $0.lastPathComponent } ?? []
            if let d = try? JSONSerialization.data(withJSONObject: names) { return String(data: d, encoding: .utf8) }
            return "[]"
        case "vaultReadBackup":
            return Self.readText(Self.bkDir(argStr(a, 0)).appendingPathComponent(Self.safe(argStr(a, 1))))
        case "vaultReadBackupB64":
            let f = Self.bkDir(argStr(a, 0)).appendingPathComponent(Self.safe(argStr(a, 1)))
            return (try? Data(contentsOf: f))?.base64EncodedString() ?? ""
        case "vaultSaveBackup":
            let name = argStr(a, 1).isEmpty ? "backup-\(Int(Date().timeIntervalSince1970 * 1000)).json" : Self.safe(argStr(a, 1))
            Self.writeText(Self.bkDir(argStr(a, 0)).appendingPathComponent(name), argStr(a, 2))
            return true
        case "vaultSaveBackupB64":
            guard let bytes = Data(base64Encoded: argStr(a, 2), options: .ignoreUnknownCharacters) else { return false }
            let name = argStr(a, 1).isEmpty ? "backup-\(Int(Date().timeIntervalSince1970 * 1000)).bin" : Self.safe(argStr(a, 1))
            do { try bytes.write(to: Self.bkDir(argStr(a, 0)).appendingPathComponent(name)); return true } catch { return false }
        case "vaultDeleteBackup":
            let f = Self.bkDir(argStr(a, 0)).appendingPathComponent(Self.safe(argStr(a, 1)))
            if !FileManager.default.fileExists(atPath: f.path) { return true }
            do { try FileManager.default.removeItem(at: f); return true } catch { return false }

        // ── 输出到人: 剪贴板 / 分享 / 看文本 / 存文件 ──
        case "clip", "setClip":
            UIPasteboard.general.string = argStr(a, 0); return nil
        case "share":
            Self.presentShare(items: [argStr(a, 0)]); return nil
        case "openText":
            Self.presentText(title: argStr(a, 0), text: argStr(a, 1)); return nil
        case "saveTextFile":
            let f = Self.dir("exports").appendingPathComponent(Self.safe(argStr(a, 0)))
            Self.writeText(f, argStr(a, 1))
            Self.presentShare(items: [f])
            return true
        case "saveBase64File":
            guard let bytes = Data(base64Encoded: argStr(a, 1), options: .ignoreUnknownCharacters) else { return false }
            let f = Self.dir("exports").appendingPathComponent(Self.safe(argStr(a, 0)))
            do { try bytes.write(to: f) } catch { return false }
            Self.presentShare(items: [f])
            return true

        // ── 原生 HTTP (异步, 回灌 __httpCb) ──
        case "httpReq", "httpReqB64":
            let wv = webView
            HttpBridge.exec(reqId: argStr(a, 0), method: argStr(a, 1), url: argStr(a, 2),
                            headersJson: argStr(a, 3), body: argStr(a, 4), b64: m == "httpReqB64") { id, json in
                DispatchQueue.main.async {
                    wv?.evaluateJavaScript("window.__httpCb&&window.__httpCb(\(HttpBridge.jsonStr(id)),\(json))")
                }
            }
            return nil

        // ── 多实例账号标签 ──
        case "openTab":
            TabManager.shared.openTab(url: argStr(a, 0), accountJson: argStr(a, 1)); return nil
        case "openAccountTab":
            TabManager.shared.openTab(url: Self.devinHome, accountJson: argStr(a, 0)); return nil
        case "openUrlTab":
            let u = argStr(a, 0)
            TabManager.shared.openTab(url: u.isEmpty ? Self.devinHome : u, accountJson: ""); return nil
        case "openEntryNewTab", "openEntryBg", "reopenAccount":
            let u = argStr(a, 1)
            TabManager.shared.openTab(url: u.isEmpty ? Self.devinHome : u, accountJson: argStr(a, 0)); return nil
        case "openAccountSession":
            var sid = argStr(a, 1).trimmingCharacters(in: .whitespaces)
            if sid.hasPrefix("devin-") { sid = String(sid.dropFirst(6)) }
            let u = sid.isEmpty ? Self.devinHome : "https://app.devin.ai/sessions/\(sid)"
            TabManager.shared.openTab(url: u, accountJson: argStr(a, 0)); return nil
        case "listTabs":
            return TabManager.shared.listJson()
        case "closeTab":
            TabManager.shared.closeTab(id: argInt(a, 0)); return nil
        case "setTabStatus", "setTabDollars", "startConvDrag":
            return nil

        // ── 远程操控开关 ──
        case "isRemoteOpsEnabled":
            return Self.readUserFile("remote-ops-flag") == "1"
        case "setRemoteOps":
            Self.writeUserFile("remote-ops-flag", argBool(a, 0) ? "1" : "0"); return nil

        // ── E2E (iOS 暂不支持加密, 明文向后兼容) ──
        case "e2eEnabled", "e2eRequired":
            return false
        case "setE2eRequired":
            return nil
        case "e2eSeal", "e2eOpen":
            return ""

        // ── 纯安卓能力: 安全默认 (页面按 falsy 优雅降级) ──
        case "setTunnelEnabled", "setLanDirect", "phoneOpenA11ySettings", "localServeResult":
            return nil
        case "isTunnelEnabled", "isLanDirect", "phoneA11yReady", "e2eSealB":
            return false
        case "tunnelStat":
            return "{\"state\":\"unsupported\"}"
        case "lanDirect", "vpnStatus":
            return ""
        case "usList", "usExportAll":
            return "[]"
        case "appCheckUpdate", "appInstallUpdate":
            return ""
        case "menu":
            return nil

        default:
            return nil
        }
    }

    // ── UI helpers (prompt 桥回调本就在主线程) ──
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let p = top?.presentedViewController { top = p }
        return top
    }

    private static func presentShare(items: [Any]) {
        DispatchQueue.main.async {
            guard let top = topViewController() else { return }
            let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = top.view
            top.present(vc, animated: true)
        }
    }

    private static func presentText(title: String, text: String) {
        DispatchQueue.main.async {
            guard let top = topViewController() else { return }
            let vc = TextViewerController(titleText: title, bodyText: text)
            top.present(UINavigationController(rootViewController: vc), animated: true)
        }
    }

    /// 轻量 toast 浮层 (对齐安卓 Toast: 瞬时提示, 不走系统通知、不求权限)。
    private static func showToast(_ text: String) {
        guard !text.isEmpty else { return }
        DispatchQueue.main.async {
            guard let v = topViewController()?.view else { return }
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 13)
            label.textColor = .white
            label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
            label.textAlignment = .center
            label.numberOfLines = 3
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            let maxW = v.bounds.width - 48
            var size = label.sizeThatFits(CGSize(width: maxW - 24, height: .greatestFiniteMagnitude))
            size.width = min(size.width + 24, maxW)
            size.height += 16
            label.frame = CGRect(x: (v.bounds.width - size.width) / 2,
                                 y: v.bounds.height - size.height - 96,
                                 width: size.width, height: size.height)
            v.addSubview(label)
            UIView.animate(withDuration: 0.3, delay: 2.2, options: []) { label.alpha = 0 } completion: { _ in label.removeFromSuperview() }
        }
    }

    private static func postNotification(title: String, text: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = text
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

/// 全屏文本查看器 (对齐安卓 N.openText: 备份/导出内容就地可读)。
final class TextViewerController: UIViewController {
    private let titleText: String
    private let bodyText: String

    init(titleText: String, bodyText: String) {
        self.titleText = titleText
        self.bodyText = bodyText
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = titleText
        view.backgroundColor = .systemBackground
        let tv = UITextView(frame: view.bounds)
        tv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tv.isEditable = false
        tv.text = bodyText
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.addSubview(tv)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }

    @objc private func close() { dismiss(animated: true) }
}
