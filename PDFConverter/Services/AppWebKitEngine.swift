import Foundation
import PDFConverterCore
import WebKit

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
        let out = try context.makeOutputURL(suffix: "", extension: "pdf")

        let pdfData: Data = try await MainActor.run {
            try renderPDF(html: html, baseURL: baseURL)
        }

        try pdfData.write(to: out)
        return ConversionResult(outputURLs: [out])
    }

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