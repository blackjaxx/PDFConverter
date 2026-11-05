import Foundation
import PDFConverterCore
import WebKit

/// App 层的 WebKit 引擎，使用 `WKWebView` 将 HTML 文件渲染为 PDF。
///
/// 这是 App 层特有的引擎（不依赖外部 CLI 工具），直接利用 macOS 内置的 WebKit 框架。
/// 遵循 `ConversionEngine` 协议，注册到 `EngineRegistry` 后，
/// `JobOrchestrator` 会在处理 `.htmlToPDF` 类型时自动调用它。
///
/// `@unchecked Sendable` 是因为 `WKWebView` 必须在主线程操作，
/// 我们通过 `MainActor.run` 保证线程安全，告知编译器信任我们的手动管理。
final class AppWebKitEngine: ConversionEngine, @unchecked Sendable {
    let kind: EngineKind = .webKit

    func supportedTypes() -> Set<ConversionType> {
        [.htmlToPDF]
    }

    /// 完整的转换流程：
    /// 1. 读取 HTML 文件内容（UTF-8 编码）
    /// 2. 获取 HTML 文件所在目录作为 `baseURL`（用于解析相对路径的资源）
    /// 3. 在主线程上通过 `WKWebView` 渲染网页
    /// 4. 将渲染的 PDF 数据写入输出文件
    func convert(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 HTML 文件")
        }
        let html = try String(contentsOf: input, encoding: .utf8)
        let baseURL = input.deletingLastPathComponent()
        let out = try context.makeOutputURL(suffix: "", extension: "pdf")

        let pdfData = try await renderPDF(html: html, baseURL: baseURL)

        try pdfData.write(to: out)
        return ConversionResult(outputURLs: [out])
    }

    /// 使用 `withCheckedThrowingContinuation` 将 WKWebView 的回调式 API
    /// 转换为 async/await 风格，使得调用方可以用 `try await` 等待结果。
    ///
    /// 这是 Swift 并发中「桥接回调 API 到 async」的标准模式：
    /// - `continuation.resume(returning:)` — 成功时返回结果
    /// - `continuation.resume(throwing:)` — 失败时抛出错误
    ///
    /// 生命周期修复（v0.5.1）：
    /// `WKWebView.navigationDelegate` 是 **weak** 引用——之前把
    /// `SimpleNavigationDelegate` 创建成临时对象后，它会在闭包返回时立即被释放，
    /// `didFinish` 永远不会回调，continuation 永远不会 resume，
    /// 任务就永久卡在「进行中」。这里用一个静态字典在渲染期间强持有
    /// webView 和 delegate，直到完成/失败/超时后才释放。
    @MainActor
    private func renderPDF(html: String, baseURL: URL, timeout: TimeInterval = 30) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let sessionID = UUID()
            // 防止双重 resume（didFail 之后 didFinish 不该再来，但超时与回调可能竞争）
            var resumed = false

            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1100))
            let delegate = SimpleNavigationDelegate(
                onError: { [weak webView] error in
                    guard !resumed else { return }
                    resumed = true
                    RenderSession.release(sessionID: sessionID)
                    webView?.stopLoading()
                    continuation.resume(throwing: error)
                },
                onFinish: {
                    guard !resumed else { return }
                    webView.createPDF(configuration: WKPDFConfiguration()) { result in
                        guard !resumed else { return }
                        resumed = true
                        RenderSession.release(sessionID: sessionID)
                        switch result {
                        case .success(let data):
                            continuation.resume(returning: data)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
            )

            // 强持有直到渲染结束，防止 webView / delegate 被提前释放
            RenderSession.retain(sessionID: sessionID, webView: webView, delegate: delegate)

            // 超时保护：页面引用了无法访问的远程资源时会一直加载，
            // 没有超时的话任务会永久挂在「进行中」
            Task { @MainActor [weak webView] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !resumed else { return }
                resumed = true
                RenderSession.release(sessionID: sessionID)
                webView?.stopLoading()
                continuation.resume(throwing: ConversionError.invalidInput(
                    "HTML 渲染超时（\(Int(timeout)) 秒）。请检查 HTML 是否引用了无法访问的远程资源。"
                ))
            }

            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }
}

/// 一次 PDF 渲染会话的强引用容器。
///
/// 解决 `WKWebView.navigationDelegate`（weak）导致的 delegate 提前释放问题：
/// 会话期间由 `activeSessions` 字典强持有 webView 和 delegate，
/// 渲染结束（完成 / 失败 / 超时）后调用 `release` 释放。
@MainActor
private final class RenderSession {
    private let webView: WKWebView
    private let delegate: SimpleNavigationDelegate

    private static var active: [UUID: RenderSession] = [:]

    private init(webView: WKWebView, delegate: SimpleNavigationDelegate) {
        self.webView = webView
        self.delegate = delegate
    }

    static func retain(sessionID: UUID, webView: WKWebView, delegate: SimpleNavigationDelegate) {
        active[sessionID] = RenderSession(webView: webView, delegate: delegate)
    }

    static func release(sessionID: UUID) {
        active.removeValue(forKey: sessionID)
    }
}

/// 封装 `WKNavigationDelegate` 回调，在页面加载完成后触发 PDF 生成。
///
/// 这个代理类被设计为「一次性使用」——创建后即绑定到单个 WKWebView，
/// 页面加载完成或失败后通过闭包回调通知调用方。
/// 三个回调方法覆盖了所有可能的导航结果：
/// - `didFinish`：正常加载完成，开始生成 PDF
/// - `didFail`：加载过程中失败（如资源加载错误）
/// - `didFailProvisionalNavigation`：在加载开始前就失败（如无效 URL、无网络）
private final class SimpleNavigationDelegate: NSObject, WKNavigationDelegate {
    private let onError: (Error) -> Void
    private let onFinish: () -> Void

    init(onError: @escaping (Error) -> Void, onFinish: @escaping () -> Void) {
        self.onError = onError
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onError(error)
    }
}