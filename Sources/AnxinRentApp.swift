import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// 应用入口：把线上 H5 包在原生壳里，得到可安装到 iPhone 的 App。
@main
struct AnxinRentApp: App {
    var body: some Scene {
        WindowGroup {
            WebShellView()
                .ignoresSafeArea(edges: [.bottom])
                .preferredColorScheme(.light)
        }
    }
}

/// 线上 H5 入口（与 manifest.json 的 h5.base = /h5/ 对应）
private let kHomeURL = "https://cc.scxjydz.com/h5/"

struct WebShellView: UIViewRepresentable {

    func makeCoordinator() -> WebCoordinator {
        WebCoordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = [.audio]
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.websiteDataStore = WKWebsiteDataStore.default()

        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // 让 H5 里的 uni-app 识别为 App 环境时也别乱认，这里只改 UA 尾巴便于排查
        webView.evaluateJavaScript("navigator.userAgent") { value, _ in
            guard let ua = value as? String else { return }
            webView.customUserAgent = ua + " AnxinRentShell/1.0"
        }

        context.coordinator.load(webView: webView, urlString: kHomeURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - WKWebView 代理

final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIDocumentPickerDelegate {

    private weak var webView: WKWebView?
    private var uploadCompletion: (([URL]?) -> Void)?

    func load(webView: WKWebView, urlString: String) {
        self.webView = webView
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 20
        // 微信登录/支付回调可能带来源校验，这里带上站点来源
        request.setValue("https://cc.scxjydz.com", forHTTPHeaderField: "Origin")
        webView.load(request)
    }

    // 允许访问范围内的站点
    private let allowedHostSuffixes = [
        "scxjydz.com",
        "bspapp.com",
        "dcloud.io",
        "dcloud.net.cn",
        "weixin.qq.com",
        "map.baidu.com",
        "apis.map.qq.com",
        "restapi.amap.com",
        "amap.com"
    ]

    private func isAllowed(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" { return true }
        return allowedHostSuffixes.contains { host.hasSuffix($0) || host.contains($0) }
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }

        switch url.scheme?.lowercased() {
        case "http", "https":
            if isAllowed(url) {
                decisionHandler(.allow)
            } else if navigationAction.targetFrame == nil {
                // 新窗口打开的第三方页（如微信 H5 支付、地图页）交给系统浏览器
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
            } else {
                // 站内可跳的第三方资源（CDN、字体、统计）直接放行
                decisionHandler(.allow)
            }
        case "tel", "sms", "mailto", "weixin", "alipays", "alipay", "itms-apps", "itms-services":
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
        default:
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure()
    }

    private func handleLoadFailure() {
        guard let webView = webView else { return }
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>
        <body style="margin:0;font-family:-apple-system;display:flex;height:100vh;align-items:center;justify-content:center;background:#f7f7f7;">
        <div style="text-align:center;color:#666;">
        <div style="font-size:17px;margin-bottom:12px;">网络不太稳定，没能加载出来</div>
        <a href="\(kHomeURL)" style="color:#1a73e8;font-size:15px;text-decoration:none;">点这里重试</a>
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: 文件/图片上传（H5 的 <input type="file">）
    // WKOpenPanelParameters 在 Xcode 16.4 的 SDK 里被标为 iOS 18.4+，但该类从 iOS 8 就已经存在，
    // 这里加 @available 只为过编译，运行时在旧系统上仍能被 WKWebView 正常回调。
    @available(iOS 18.4, *)
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {

        uploadCompletion = completionHandler
        let types: [UTType] = [.image, .movie, .pdf, .data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = parameters.allowsMultipleSelection
        picker.delegate = self
        topViewController()?.present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        uploadCompletion?(urls)
        uploadCompletion = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        uploadCompletion?(nil)
        uploadCompletion = nil
    }

    // MARK: JS alert / confirm

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        topViewController()?.present(alert, animated: true, completion: nil)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        topViewController()?.present(alert, animated: true, completion: nil)
    }
}

// MARK: - 工具

func topViewController() -> UIViewController? {
    let keyWindow = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }

    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
        top = presented
    }
    return top
}
