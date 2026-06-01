import Foundation

/// 基于 Tesseract OCR 引擎的转换引擎，将图片 PDF 转为可搜索的 PDF。
///
/// Tesseract 是 Google 维护的开源 OCR（光学字符识别）引擎，支持 100+ 种语言。
/// 这个引擎将 PDF 的每一页作为图片进行 OCR 识别，然后将识别出的文本层叠加到
/// 原始图片之上，生成"可搜索 PDF"——用户可以在阅读器中搜索和选择文字。
///
/// ## 什么是可搜索 PDF？
/// 普通的图片 PDF（扫描文档）在阅读器中只是一张静态图片，无法搜索或复制文字。
/// OCR 处理会在每页的图片下面添加一层透明的文字层，使得阅读器可以索引和搜索文本，
/// 但视觉效果与原图完全一致。
///
/// ## OCR 语言参数格式
///
/// 语言参数通过 `parameters.ocrLanguages` 传入，是一个字符串数组（如 `["chi_sim", "eng"]`），
/// 多个语言用 `+` 连接后传给 Tesseract。这表示 Tesseract 会同时使用简体中文和英文
/// 的识别模型，适合处理中英混合的文档。
///
/// 常用语言代码：
/// - `chi_sim` — 简体中文
/// - `chi_tra` — 繁体中文
/// - `eng`     — 英文
/// - `jpn`     — 日文
/// - `kor`     — 韩文
///
/// ## Tesseract 命令行参数
/// ```
/// tesseract input.pdf output_base -l chi_sim+eng pdf
/// ```
/// - `input.pdf`：输入文件（PDF 或图片）
/// - `output_base`：输出文件基础名（不含扩展名，Tesseract 会自动加 `.pdf`）
/// - `-l chi_sim+eng`：OCR 语言组合
/// - `pdf`：输出格式为可搜索 PDF
public struct TesseractEngine: ConversionEngine {
    public let kind: EngineKind = .tesseract

    private let tesseract = BundledTool(name: "tesseract", relativePath: "tesseract/tesseract", engine: .tesseract)

    public init() {}

    public func supportedTypes() -> Set<ConversionType> {
        [.ocrSearchablePDF]
    }

    public func convert(context: ConversionContext) async throws -> ConversionResult {
        guard context.job.type == .ocrSearchablePDF else {
            throw ConversionError.unsupportedType(context.job.type)
        }
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF 或图片")
        }

        let tool = try ToolLocator.shared.require(tesseract)
        // 将多个语言用 + 连接，例如 ["chi_sim", "eng"] → "chi_sim+eng"
        let langs = context.job.parameters.ocrLanguages.joined(separator: "+")
        let outBase = context.workDirectory.appendingPathComponent("ocr_output")
        let out = try context.makeOutputURL(suffix: "_ocr", extension: "pdf")

        // Tesseract 需要 TESSDATA_PREFIX 环境变量来定位语言数据文件
        let tessdataDir = tool.deletingLastPathComponent().appendingPathComponent("tessdata")
        let env = ["TESSDATA_PREFIX": tessdataDir.path]

        // Tesseract 参数说明：
        // input.pdf              → 输入文件
        // ocr_output             → 输出基础名（Tesseract 自动加 .pdf 扩展名）
        // -l chi_sim+eng         → OCR 识别语言
        // pdf                    → 输出类型
        let args = [input.path, outBase.path, "-l", langs, "pdf"]
        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args, environment: env, currentDirectory: context.workDirectory)

        // Tesseract 生成的文件名为 `ocr_output.pdf`（会自动追加扩展名）
        let generated = outBase.appendingPathExtension("pdf")
        if FileManager.default.fileExists(atPath: generated.path) {
            if FileManager.default.fileExists(atPath: out.path) {
                try FileManager.default.removeItem(at: out)
            }
            try FileManager.default.moveItem(at: generated, to: out)
        }

        guard FileManager.default.fileExists(atPath: out.path) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }
}