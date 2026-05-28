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

        let pdfData: Data = try await MainActor.run {
            try renderPDF(html: html, baseURL: baseURL)
        }

        try pdfData.write(to: out)
        return ConversionResult(outputURLs: [out])
    }

    /// 使用 `withCheckedThrowingContinuation` 将 WKWebView 的回调式 API
    /// 转换为 async/await 风格，使得调用方可以用 `try await` 等待结果。
    ///
    /// 这是 Swift 并发中「桥接回调 API 到 async」的标准模式：
    /// - `continuation.resume(returning:)` — 成功时返回结果
    /// - `continuation.resume(throwing:)` — 失败时抛出错误
    @MainActor
    private func renderPDF(html: String, baseURL: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1100))

            webView.navigationDelegate = SimpleNavigationDelegate(
                onError: { continuation.resume(throwing: $0) },
                onFinish: {
                    webView.createPDF(configuration: WKPDFConfiguration()) { result, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let result {
                            continuation.resume(returning: result)
                        } else {
                            continuation.resume(throwing: ConversionError.outputMissing("PDF from WebKit"))
                        }
                    }
                }
            )

            webView.loadHTMLString(html, baseURL: baseURL)
        }
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