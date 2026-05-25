import Foundation

public enum PDFTextExtractor {
    private static let pdftotext = BundledTool(name: "pdftotext", relativePath: "poppler/pdftotext", engine: .poppler)

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

    public static func truncate(_ text: String, maxChars: Int) -> (text: String, truncated: Bool) {
        guard text.count > maxChars else { return (text, false) }
        let end = text.index(text.startIndex, offsetBy: maxChars)
        return (String(text[..<end]), true)
    }
}
