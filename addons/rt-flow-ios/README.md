# rt-flow-ios · Devin Cloud 手机版 iOS 壳 (IPA)

> 安卓版 [`addons/rt-flow-app`](../rt-flow-app/README.md) 的 iOS 姊妹壳。**JS 资产零拷贝共用**
> 安卓的 `app/src/main/assets/engine/`（切号面板 / 穿透面板 / 常驻引擎 / Devin Cloud 全功能 JS），
> 原生层用 Swift + WKWebView 重写安卓 `@JavascriptInterface` 桥的核心子集。

## 核心三合一（iOS MVP 范围）

| 能力 | 实现 |
|---|---|
| **切号 + Devin Cloud 全功能面板** | 主 WKWebView 加载 `daopan.html`/`switch.html`（与安卓同一套页面），`window.Native.*` 经同步 prompt 桥落到 Swift |
| **内网穿透（被远程驱动）** | 隐藏引擎 WKWebView 跑 `engine.html` + `relay-app.js`（页内出站 WSS 连 dao-relay 中继，与安卓 RelayService 引擎同源） |
| **网页多实例** | `N.openTab(url, account)` → 每账号独立 WKWebView（nonPersistent 数据仓）+ documentStart 注入该号 auth1 登录态（复刻安卓 `TabActivity.buildInjection`） |

安卓特有能力（VPN / Shizuku / 无障碍系统级接管 / phone* 本体操控 / cloudflared 本地隧道）在 iOS
原生返回安全默认值，页面按 falsy 优雅降级隐藏对应入口。

## 架构

```
App/
├── AppDelegate.swift / SceneDelegate.swift   # 应用入口
├── MainViewController.swift                  # 主面板 webview (daopan.html)
├── EngineController.swift                    # 隐藏常驻引擎 webview (engine.html · 中继客户端)
├── NativeBridge.swift                        # window.Native 原生实现 (同步 prompt 桥分发)
├── HttpBridge.swift                          # 原生 HTTP (绕 CORS · __httpCb 回灌, 对齐安卓 HttpBridge.java)
├── TabManager.swift                          # 多实例账号标签 + auth1 注入
├── AssetSchemeHandler.swift                  # rtflow://engine/* → 安卓 engine 资产 (Bundle 内共用)
└── Shim/native-shim.js                       # documentStart 注入: window.Native.* → prompt 同步桥
```

**同步桥原理**：WKWebView 无安卓 `@JavascriptInterface` 的同步返回能力，用 `window.prompt()`
（WKUIDelegate 同步回包）承载 `Native.*` 调用 — 页面零改动。异步网络走 `httpReq` →
`window.__httpCb` 回灌，与安卓完全同协议。

## 构建

```bash
cd addons/rt-flow-ios
xcodegen generate        # project.yml → DevinCloudMobile.xcodeproj
xcodebuild -project DevinCloudMobile.xcodeproj -scheme DevinCloudMobile \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

CI（`.github/workflows/ios-release.yml`）在 macOS runner 上自动构建**未签名 IPA** 并发到
Release tag `rtflow-ios-v<版本>`（版本号唯一事实源 = `project.yml` 的 `MARKETING_VERSION`）。

## 安装（重要）

未签名 IPA **不能直接安装**，需自签工具之一：

- **巨魔 TrollStore**（永久签名，需特定 iOS 版本）
- **AltStore / SideStore**（免费 Apple ID 自签，7 天续签）
- **Sideloadly / 爱思助手**（电脑端自签安装）

## 首次使用

与安卓版一致：打开 App → 穿透面板填入中继 `URL / Token / Session` → 保存自动连接；
切号面板导入账号即可多实例开号。
