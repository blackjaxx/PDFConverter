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
    public init() {}
    public let kind: EngineKind = .tesseract

    private let tesseract = BundledTool(name: "tesseract", relativePath: "tesseract/tesseract", engine: .tesseract)

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

        // 关键修复（v0.4.2）：TESSDATA_PREFIX 必须以 "/" 结尾
        // Tesseract 4.x 行为：TESSDATA_PREFIX 是 tessdata 目录的**父目录**
        // 即：PREFIX/tessdata/chi_sim.traineddata 这种结构
        // 我们打包的目录结构是 Resources/tools/tesseract/tessdata/*.traineddata
        // 所以 PREFIX 应为 tesseract 目录的路径（包含末尾斜杠）
        let tessdataParent = tool.deletingLastPathComponent()  // .../tools/tesseract/
        let env: [String: String] = [
            "TESSDATA_PREFIX": tessdataParent.path + "/"
        ]

        // 用 input stem 命名输出（避免与其他转换任务冲突）
        let inputStem = input.deletingPathExtension().lastPathComponent
        let outBase = context.workDirectory.appendingPathComponent(inputStem + "_ocr")
        let out = try context.makeOutputURL(suffix: "_ocr", extension: "pdf")

        // 启动转换时把进度推到 0.1
        await JobOrchestrator.shared.updateProgress(id: context.job.id, progress: 0.1)

        // Tesseract 参数：
        // input.pdf  → 输入文件
        // outBase    → 输出基础名（Tesseract 自动加 .pdf 扩展名）
        // -l langs   → OCR 识别语言
        // pdf        → 输出类型
        let langs = context.job.parameters.ocrLanguages.joined(separator: "+")
        let args = [input.path, outBase.path, "-l", langs, "pdf"]
        _ = try await ProcessRunner.runChecked(
            executable: tool,
            arguments: args,
            environment: env,
            currentDirectory: context.workDirectory
        )

        // OCR 完成，推到 0.9
        await JobOrchestrator.shared.updateProgress(id: context.job.id, progress: 0.9)

        // Tesseract 生成的文件名是 `<outBase>.pdf`
        let generated = outBase.appendingPathExtension("pdf")
        guard FileManager.default.fileExists(atPath: generated.path) else {
            throw ConversionError.outputMissing(generated.path)
        }

        if FileManager.default.fileExists(atPath: out.path) {
            try FileManager.default.removeItem(at: out)
        }
        try FileManager.default.moveItem(at: generated, to: out)

        return ConversionResult(outputURLs: [out])
    }
}