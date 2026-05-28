import Foundation
import PDFConverterCore

/// App 层的 DeepSeek AI 引擎，实现 PDF → AI 处理（摘要/翻译/Markdown）的完整流程。
///
/// 处理流程：
/// 1. 验证 DeepSeek API Key 是否已配置
/// 2. 验证输入文件是否为 PDF
/// 3. 使用 `PDFTextExtractor.extractText`（内部调用 pdftotext CLI）提取 PDF 正文
/// 4. 按 `aiMaxInputChars` 限制截断文本
/// 5. 根据转换类型生成提示词（system prompt + user prompt）
/// 6. 通过 `DeepSeekClient` 发送 HTTP 请求到 DeepSeek API
/// 7. 将返回结果保存为 `.md` 文件
///
/// 这是 App 层引擎，不依赖外部 CLI（除了 pdftotext），通过 HTTP 调用云端 AI。
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

    /// 根据转换类型生成不同的系统提示词（system prompt）和用户提示词（user prompt）。
    ///
    /// 三种类型的提示词设计思路：
    /// - **摘要**（.pdfAISummary）：让 AI 扮演文档分析助手，输出结构化摘要和要点列表
    /// - **翻译**（.pdfAITranslate）：让 AI 扮演专业翻译，保持段落结构，专有名词保留原文
    /// - **转 Markdown**（.pdfAIToMarkdown）：让 AI 扮演文档结构化专家，转换为规范的 Markdown
    ///
    /// 所有提示词都强调「不要编造正文中不存在的内容」，避免 AI 产生幻觉。
    /// 当文本被截断时，会在 user prompt 中加入截断提示。
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