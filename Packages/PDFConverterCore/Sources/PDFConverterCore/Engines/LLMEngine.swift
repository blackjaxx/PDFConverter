import Foundation

/// Placeholder; app registers `AppLLMEngine` (DeepSeek) via custom `EngineRegistry`.
public struct LLMEngine: ConversionEngine {
    public let kind: EngineKind = .deepSeek

    public func supportedTypes() -> Set<ConversionType> {
        [.pdfAISummary, .pdfAITranslate, .pdfAIToMarkdown]
    }

    public func convert(context: ConversionContext) async throws -> ConversionResult {
        throw ConversionError.aiNotConfigured(
            "请在应用设置中配置 DeepSeek API Key，并确保已注册 AppLLMEngine。"
        )
    }
}
