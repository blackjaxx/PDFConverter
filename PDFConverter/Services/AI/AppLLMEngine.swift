import Foundation
import PDFConverterCore

final class AppLLMEngine: ConversionEngine, @unchecked Sendable {
    let kind: EngineKind = .deepSeek

    func supportedTypes() -> Set<ConversionType> {
        [.pdfAISummary, .pdfAITranslate, .pdfAIToMarkdown]
    }

    func convert(context: ConversionContext) async throws -> ConversionResult {
        guard let apiKey = DeepSeekSettings.apiKey, DeepSeekSettings.isConfigured else {
            throw ConversionError.aiNotConfigured(
                "请先在设置 → DeepSeek 中填写 API Key（https://platform.deepseek.com）"
            )
        }

        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择一个 PDF 文件")
        }
        guard input.pathExtension.lowercased() == "pdf" else {
            throw ConversionError.invalidInput("AI 功能目前仅支持 PDF 文件")
        }

        let rawText = try await PDFTextExtractor.extractText(from: input, toolsRoot: context.toolsRoot)
        let maxChars = max(1000, context.job.parameters.aiMaxInputChars)
        let (chunk, truncated) = PDFTextExtractor.truncate(rawText, maxChars: maxChars)

        let client = DeepSeekClient(
            baseURL: DeepSeekSettings.baseURL,
            apiKey: apiKey,
            model: DeepSeekSettings.model
        )

        let (system, user, ext) = prompts(for: context.job.type, text: chunk, truncated: truncated, job: context.job)
        let result = try await client.complete(system: system, user: user)

        let outDir = context.job.outputDirectory ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let suffix: String = {
            switch context.job.type {
            case .pdfAISummary: return "_summary"
            case .pdfAITranslate: return "_translated"
            case .pdfAIToMarkdown: return "_md"
            default: return "_ai"
            }
        }()
        let out = outDir.appendingPathComponent(stem + suffix).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: out.path) {
            try FileManager.default.removeItem(at: out)
        }
        try result.write(to: out, atomically: true, encoding: .utf8)

        var logs = "DeepSeek model: \(DeepSeekSettings.model)"
        if truncated { logs += "\n（原文已截断至 \(maxChars) 字符）" }
        return ConversionResult(outputURLs: [out], logs: logs)
    }

    private func prompts(
        for type: ConversionType,
        text: String,
        truncated: Bool,
        job: ConversionJob
    ) -> (system: String, user: String, ext: String) {
        let truncNote = truncated ? "\n\n[注：以下为截断后的正文片段]" : ""
        let extra = job.parameters.aiCustomInstruction.map { "\n\n用户附加要求：\($0)" } ?? ""

        switch type {
        case .pdfAISummary:
            return (
                "你是专业的文档分析助手。根据用户提供的 PDF 正文，用简洁清晰的中文写出结构化摘要（含要点列表）。不要编造正文中不存在的内容。",
                "请为以下 PDF 正文生成摘要：\(truncNote)\n\n\(text)\(extra)",
                "md"
            )
        case .pdfAITranslate:
            let lang = job.parameters.aiTargetLanguage
            return (
                "你是专业翻译。将用户提供的正文准确翻译为\(lang)，保持段落结构，专有名词可保留原文并在括号注明。",
                "请将以下正文翻译为\(lang)：\(truncNote)\n\n\(text)\(extra)",
                "md"
            )
        case .pdfAIToMarkdown:
            return (
                "你是文档结构化专家。将正文整理为规范的 Markdown（标题、列表、表格尽量还原），不要添加正文中没有的信息。",
                "请将以下 PDF 正文转为 Markdown：\(truncNote)\n\n\(text)\(extra)",
                "md"
            )
        default:
            return ("", text, "txt")
        }
    }
}
