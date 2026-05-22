import Foundation

/// HTML → PDF is rendered in the app layer (WKWebView). Core holds the type mapping;
/// the app registers `AppWebKitEngine` conforming to `ConversionEngine` at launch.
public struct WebKitEngine: ConversionEngine {
    public let kind: EngineKind = .webKit

    public func supportedTypes() -> Set<ConversionType> {
        [.htmlToPDF]
    }

    public func convert(context: ConversionContext) async throws -> ConversionResult {
        throw ConversionError.invalidInput(
            "HTML → PDF 需在应用内注册 AppWebKitEngine。请在 Xcode 目标 PDFConverter 中实现 WebKit 渲染。"
        )
    }
}
