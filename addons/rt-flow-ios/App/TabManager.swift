import UIKit
import WebKit

/// 多实例账号标签 — 每个标签一个独立 WKWebView (nonPersistent 数据仓, 各登各号互不串号),
/// documentStart 注入该账号 auth1 登录态 (对齐安卓 TabActivity.buildInjection)。
final class TabManager {
    static let shared = TabManager()

    private var seq = 1
    private(set) var tabs: [Int: (label: String, vc: TabViewController)] = [:]

    func openTab(url: String, accountJson: String) {
        DispatchQueue.main.async {
            let id = self.seq
            self.seq += 1
            var label = ""
            if let d = accountJson.data(using: .utf8),
               let acc = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                label = (acc["email"] as? String) ?? (acc["id"] as? String) ?? ""
            }
            let vc = TabViewController(tabId: id, url: url, accountJson: accountJson)
            self.tabs[id] = (label, vc)
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .fullScreen
            self.topViewController()?.present(nav, animated: true)
        }
    }

    func listJson() -> String {
        let arr = tabs.map { ["tabId": $0.key, "account": $0.value.label] as [String: Any] }
        if let d = try? JSONSerialization.data(withJSONObject: arr) { return String(data: d, encoding: .utf8) ?? "[]" }
        return "[]"
    }

    func closeTab(id: Int) {
        DispatchQueue.main.async {
            if let entry = self.tabs.removeValue(forKey: id) {
                entry.vc.dismiss(animated: true)
            }
        }
    }

    func tabClosed(id: Int) { tabs.removeValue(forKey: id) }

    private func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let p = top?.presentedViewController { top = p }
        return top
    }
}

final class TabViewController: UIViewController, WKUIDelegate {
    private let tabId: Int
    private let urlString: String
    private let accountJson: String
    private var webView: WKWebView!

    init(tabId: Int, url: String, accountJson: String) {
        self.tabId = tabId
        self.urlString = url.isEmpty ? "https://app.devin.ai/" : url
        self.accountJson = accountJson
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        var token = "", org = "", uid = "", orgName = "", label = ""
        if let d = accountJson.data(using: .utf8),
           let acc = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
            token = acc["auth1"] as? String ?? ""
            org = acc["orgId"] as? String ?? ""
            uid = acc["userId"] as? String ?? ""
            orgName = acc["orgName"] as? String ?? ""
            label = (acc["email"] as? String) ?? (acc["id"] as? String) ?? ""
        }
        title = "Devin Cloud · \(label)"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTab))

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent() // 各标签独立数据仓, 多实例互不串号
        config.allowsInlineMediaPlayback = true
        let script = Self.buildInjection(token: token, userId: uid, org: org, orgName: orgName)
        config.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.uiDelegate = self
        view.addSubview(webView)
        webView.load(URLRequest(url: URL(string: urlString) ?? URL(string: "https://app.devin.ai/")!))
    }

    @objc private func closeTab() {
        TabManager.shared.tabClosed(id: tabId)
        dismiss(animated: true)
    }

    // window.open / target=_blank → 本 webview 内打开
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
        return nil
    }

    /// document_start 注入 — 复刻安卓 TabActivity.buildInjection (= 桌面 devin_proxy.js 配方):
    ///   ① iso 垫片: dao 登录态键 localStorage→sessionStorage (本标签私有)
    ///   ② 种入 SPA 登录态: auth1_session={token,userId} + 迁移键 + known-org-ids + post-auth-v3 守键
    ///   ③ cookie webapp_logged_in=true
    ///   ④ fetch/XHR 强制注入 Authorization:Bearer + x-cog-org-id
    static func buildInjection(token: String, userId: String, org: String, orgName: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        }
        let t = esc(token), u = esc(userId), o = esc(org), on = esc(orgName)
        return "(function(){try{" +
            "var __a1='\(t)',__uid='\(u)',__org='\(o)',__orgName='\(on)';" +
            "try{sessionStorage.setItem('__dao_tab_isolated__','1');}catch(e){}" +
            "(function(){var DAO=/^(auth1_session$|migrated-to-unscoped-auth0-token|known-org-ids-|last-internal-org-for-external-org|post-auth-v3-)/;" +
            "var P=Storage.prototype,ls=window.localStorage,ss=window.sessionStorage,g=P.getItem,st=P.setItem,rm=P.removeItem;" +
            "P.getItem=function(k){if(this===ls&&DAO.test(k))return g.call(ss,k);return g.call(this,k);};" +
            "P.setItem=function(k,v){if(this===ls&&DAO.test(k))return st.call(ss,k,v);return st.call(this,k,v);};" +
            "P.removeItem=function(k){if(this===ls&&DAO.test(k))return rm.call(ss,k);return rm.call(this,k);};})();" +
            "if(__a1){" +
            "localStorage.setItem('auth1_session',JSON.stringify({token:__a1,userId:__uid}));" +
            "localStorage.setItem('migrated-to-unscoped-auth0-token-2025-12-18','true');" +
            "if(__uid)localStorage.setItem('known-org-ids-'+__uid,JSON.stringify([__org]));" +
            "if(__org)localStorage.setItem('last-internal-org-for-external-org-v1-null',__org);" +
            "if(__org&&__uid&&__orgName){var __k='post-auth-v3-null-'+__uid+'-org_name-'+__orgName;" +
            "if(!localStorage.getItem(__k))localStorage.setItem(__k,JSON.stringify({externalOrgId:null,userId:__uid,internalOrgId:__org,orgName:__orgName,result:{resolved_external_org_id:null,org_id:__org,org_name:__orgName,is_valid_resource:true}}));}" +
            "}" +
            "try{document.cookie='webapp_logged_in=true; path=/; max-age=31536000; SameSite=Lax';}catch(e){}" +
            "function isApi(u){try{return /app\\.devin\\.ai\\/api\\//.test(u)||u.indexOf('/api/')===0;}catch(e){return false;}}" +
            "var of=window.fetch;window.fetch=function(input,init){try{var url=(typeof input==='string')?input:(input&&input.url)||'';if(__a1&&isApi(url)){init=init||{};var h=new Headers(init.headers||(typeof input!=='string'&&input.headers)||{});if(!h.has('Authorization'))h.set('Authorization','Bearer '+__a1);if(__org&&!h.has('x-cog-org-id'))h.set('x-cog-org-id',__org);init.headers=h;}}catch(e){}return of.call(this,input,init);};" +
            "var oo=XMLHttpRequest.prototype.open,osd=XMLHttpRequest.prototype.send;" +
            "XMLHttpRequest.prototype.open=function(m,u){this.__api=isApi(u);return oo.apply(this,arguments);};" +
            "XMLHttpRequest.prototype.send=function(b){try{if(__a1&&this.__api){this.setRequestHeader('Authorization','Bearer '+__a1);if(__org)this.setRequestHeader('x-cog-org-id',__org);}}catch(e){}return osd.apply(this,arguments);};" +
            "}catch(e){}})();"
    }
}
