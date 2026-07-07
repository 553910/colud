/* native-shim.js · iOS 壳注入 (documentStart)
 * 把 window.Native.* 映射到 Swift NativeBridge 的同步 prompt 桥:
 *   prompt("__dao_native__", JSON{m,a}) → WKUIDelegate 同步处理 → JSON{r}
 * 与安卓 @JavascriptInterface 同名同语义, 引擎/面板页 (engine.html/switch.html/…) 零改动直跑。
 *
 * 用 Proxy 兜底任意方法名 (安卓 Bridge 对象本就"方法全在"): 未原生实现的返回安全默认 (null/false),
 * 页面按 falsy 优雅降级, 不会因 N.someMethod 为 undefined 而 TypeError。
 * 异步方法 (httpReq/httpReqB64) 原生立即返回, 结果经 window.__httpCb 回灌。
 */
(function () {
  if (window.Native && window.Native.__ios) return;

  function call(m, args) {
    try {
      var r = window.prompt("__dao_native__", JSON.stringify({ m: m, a: args || [] }));
      if (r == null || r === "") return null;
      var d = JSON.parse(r);
      return (d && Object.prototype.hasOwnProperty.call(d, "r")) ? d.r : null;
    } catch (e) {
      try { console.error("[native-shim] " + m, e); } catch (_) {}
      return null;
    }
  }

  var cache = { __ios: true };
  function method(m) {
    if (!cache[m]) {
      cache[m] = function () { return call(m, Array.prototype.slice.call(arguments)); };
    }
    return cache[m];
  }

  var handler = {
    get: function (_t, prop) {
      if (prop === "__ios") return true;
      if (typeof prop !== "string") return undefined;
      // 避免把 then 之类当成 thenable (防被 Promise 误当), 以及 Symbol 探测
      if (prop === "then" || prop === "toJSON") return undefined;
      return method(prop);
    },
    has: function () { return true; }
  };

  window.Native = new Proxy(cache, handler);
})();
