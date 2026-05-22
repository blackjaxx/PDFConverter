import Foundation
import PDFConverterCore
import WebKit

/// Renders local HTML to PDF using WKWebView (must run on main actor).
final class AppWebKitEngine: ConversionEngine, @unchecked Sendable {
    let kind: EngineKind = .webKit

    func supportedTypes() -> Set<ConversionType> {
        [.htmlToPDF]
    }

    func convert(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 HTML 文件")
        }
        let html = try String(contentsOf: input, encoding: .utf8)
        let baseURL = input.deletingLastPathComponent()
        let out = (context.job.outputDirectory ?? baseURL)
            .appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".pdf")

        let pdfData: Data = try await MainActor.run {
            try renderPDF(html: html, baseURL: baseURL)
        }

        try pdfData.write(to: out)
        return ConversionResult(outputURLs: [out])
    }

    @MainActor
    private func renderPDF(html: String, baseURL: URL) throws -> Data {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1100))
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        var pdfData: Data?

        webView.navigationDelegate = SimpleNavigationDelegate { error in
            loadError = error
            semaphore.signal()
        } onFinish: {
            webView.createPDF(configuration: WKPDFConfiguration()) { result, error in
                if let error { loadError = error }
                else if let result { pdfData = result }
                semaphore.signal()
            }
        }

        webView.loadHTMLString(html, baseURL: baseURL)
        _ = semaphore.wait(timeout: .now() + 60)

        if let loadError { throw loadError }
        guard let pdfData else {
            throw ConversionError.outputMissing("PDF from WebKit")
        }
        return pdfData
    }
}

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
