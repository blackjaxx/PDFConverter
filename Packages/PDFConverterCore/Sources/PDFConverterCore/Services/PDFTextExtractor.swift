import Foundation

/// 使用 Poppler 的 `pdftotext` 工具从 PDF 提取文本内容。
///
/// 这个工具类主要用于 AI 功能的前置步骤——在调用 DeepSeek API 进行摘要、
/// 翻译或 Markdown 转换之前，需要先从 PDF 中提取纯文本作为输入。
///
/// 为什么需要独立的文本提取器？
/// - AI 引擎需要的是纯文本，不是 PDF 二进制，所以必须先提取
/// - 提取逻辑与 AI 调用逻辑分离，符合单一职责原则
/// - 截断功能帮助控制 API token 消耗，避免发送过大的文档
public enum PDFTextExtractor {
    /// pdftotext 工具的 BundledTool 描述
    private static let pdftotext = BundledTool(name: "pdftotext", relativePath: "poppler/pdftotext", engine: .poppler)

    /// 从 PDF 文件中提取纯文本内容。
    ///
    /// ## 执行流程
    /// 1. 通过 ``ToolLocator`` 查找 `pdftotext` 可执行文件
    /// 2. 创建临时输出文件（`/tmp/<UUID>.txt`）
    /// 3. 调用 `pdftotext input.pdf output.txt` 进行提取
    /// 4. 读取临时文件内容
    /// 5. 通过 `defer` 清理临时文件
    /// 6. 去除首尾空白字符
    ///
    /// - Parameters:
    ///   - pdfURL: PDF 文件的 URL
    ///   - toolsRoot: 工具集根目录
    /// - Returns: 提取到的纯文本内容
    /// - Throws: 工具未找到、提取失败、或内容为空时抛出相应错误
    public static func extractText(from pdfURL: URL, toolsRoot: URL?) async throws -> String {
        let tool = try ToolLocator.shared.require(pdftotext)
        let tempOut = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")

        defer { try? FileManager.default.removeItem(at: tempOut) }

        _ = try await ProcessRunner.runChecked(
            executable: tool,
            arguments: [pdfURL.path, tempOut.path]
        )

        let text = try String(contentsOf: tempOut, encoding: .utf8)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConversionError.invalidInput("未能从 PDF 提取文本，请尝试 OCR 或扫描质量更好的文件")
        }
        return trimmed
    }

    /// 截断文本以控制发送给 AI 的字符数。
    ///
    /// LLM API 按照 token 数量计费，过长的输入不仅费用高，响应也慢。
    /// 这个方法在字符级别进行粗略截断（并非精确的 token 截断），
    /// 对于大多数中文和英文混合文档，字符数大致与 token 数成正比。
    ///
    /// - Parameters:
    ///   - text: 原始文本
    ///   - maxChars: 最大保留字符数
    /// - Returns: `(截断后的文本, 是否发生了截断)` 元组。
    ///   UI 层可以根据 `truncated` 标志提示用户文档内容被截断了。
    public static func truncate(_ text: String, maxChars: Int) -> (text: String, truncated: Bool) {
        guard text.count > maxChars else { return (text, false) }
        let end = text.index(text.startIndex, offsetBy: maxChars)
        return (String(text[..<end]), true)
    }
}