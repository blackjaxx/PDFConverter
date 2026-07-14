import Foundation

/// 基于 Poppler 工具集的转换引擎，处理 PDF 到图片和文本的转换。
///
/// Poppler 是一个开源的 PDF 渲染库，提供了两个关键的命令行工具：
/// - `pdftoppm`：将 PDF 页面渲染为图片（PNG、JPEG、TIFF 等格式）
/// - `pdftotext`：从 PDF 中提取纯文本
///
/// 这些工具需要预先打包进 App Bundle 中（通过 `Scripts/bundle-tools.sh` 脚本），
/// 或者在开发阶段通过 Homebrew 安装（`brew install poppler`）。
///
/// 为什么选择 Poppler 而不是其他 PDF 渲染库？
/// - macOS 自带的 PDFKit 只能创建和修改 PDF，**不能将 PDF 渲染为高分辨率位图**。
///   `pdftoppm` 支持自定义 DPI 和页码范围，输出质量远高于截屏方案。
/// - `pdftotext` 提取的文本保留了原始的排版顺序，适合后续的 AI 处理。
public struct PopplerEngine: ConversionEngine {
    public init() {}
    public let kind: EngineKind = .poppler

    private let pdftoppm = BundledTool(name: "pdftoppm", relativePath: "poppler/pdftoppm", engine: .poppler)
    private let pdftotext = BundledTool(name: "pdftotext", relativePath: "poppler/pdftotext", engine: .poppler)

    public func supportedTypes() -> Set<ConversionType> {
        [.pdfToPNG, .pdfToJPEG, .pdfToTIFF, .pdfToText]
    }

    public func convert(context: ConversionContext) async throws -> ConversionResult {
        switch context.job.type {
        case .pdfToPNG, .pdfToJPEG, .pdfToTIFF:
            return try await pdfToImages(context: context)
        case .pdfToText:
            return try await pdfToText(context: context)
        default:
            throw ConversionError.unsupportedType(context.job.type)
        }
    }

    /// 将 PDF 渲染为图片。
    ///
    /// 调用 `pdftoppm` 工具，支持以下参数：
    /// - `-png` / `-jpeg` / `-tiff`：输出格式
    /// - `-r <dpi>`：输出分辨率（从 `parameters.dpi` 获取，默认 150）
    /// - `-f <start>` / `-l <end>`：页码范围（从 `parameters.pageRange` 获取，可选）
    ///
    /// 输出文件命名格式：`<input-stem>-1.png`、`<input-stem>-2.png` 等。
    /// 生成的文件从临时工作目录移动到目标输出目录。
    ///
    /// v0.4.2 修复：
    /// - 输出文件前缀使用 input 文件的 stem（如 `report-1.png` 而非 `page-1.png`）
    /// - 转换过程中按页数比例更新 JobOrchestrator 进度
    private func pdfToImages(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF")
        }
        let tool = try ToolLocator.shared.require(pdftoppm)
        let dpi = String(context.job.parameters.dpi)
        let format: String
        let ext: String
        switch context.job.type {
        case .pdfToPNG: format = "png"; ext = "png"
        case .pdfToJPEG: format = "jpeg"; ext = "jpg"
        case .pdfToTIFF: format = "tiff"; ext = "tiff"
        default: throw ConversionError.unsupportedType(context.job.type)
        }

        // 关键修复（v0.4.2）：用 input 文件的 stem 命名输出
        // 例如 input "report.pdf" → "report-1.png"、"report-2.png"
        let inputStem = input.deletingPathExtension().lastPathComponent
        let prefix = context.workDirectory.appendingPathComponent(inputStem).path

        var args = ["-\(format)", "-r", dpi, input.path, prefix]

        // pdftoppm 的参数顺序是 [options] input output-prefix
        if let range = context.job.parameters.pageRange {
            args.insert(contentsOf: ["-f", String(range.start)], at: 0)
            if let end = range.end {
                args.insert(contentsOf: ["-l", String(end)], at: 2)
            }
        }

        // 启动转换时把进度推到 0.1（避免一直显示 0.05）
        await JobOrchestrator.shared.updateProgress(id: context.job.id, progress: 0.1)

        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args, currentDirectory: context.workDirectory)

        // 转换完成，推到 0.9（move 到目标目录后推到 1.0）
        await JobOrchestrator.shared.updateProgress(id: context.job.id, progress: 0.9)

        // 扫描临时目录中的输出文件，按文件名排序
        let files = try FileManager.default.contentsOfDirectory(at: context.workDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == ext && $0.lastPathComponent.hasPrefix(inputStem) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !files.isEmpty else {
            throw ConversionError.outputMissing(ext)
        }

        // 将生成的文件从临时目录移动到目标目录
        let destDir = context.job.outputDirectory ?? input.deletingLastPathComponent()
        var outputs: [URL] = []
        for file in files {
            let dest = destDir.appendingPathComponent(file.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: file, to: dest)
            outputs.append(dest)
        }
        return ConversionResult(outputURLs: outputs)
    }

    /// 从 PDF 中提取纯文本。
    ///
    /// 调用 `pdftotext` 工具，将提取结果直接写入输出文件。
    /// 如果指定了页码范围，使用 `-f` 和 `-l` 参数限制提取范围。
    ///
    /// - Note: 对于扫描版 PDF（图片内容），`pdftotext` 无法提取文本，
    ///   此时应使用 ``TesseractEngine`` 的 OCR 功能。
    ///
    /// v0.4.2 修复：
    /// - 转换过程中更新进度
    /// - 移除自动添加的 ".txt" 扩展名（pdftotext 不会自动加）
    private func pdfToText(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF")
        }
        let tool = try ToolLocator.shared.require(pdftotext)
        // 修复（v0.4.2）：输出文件名用 input stem 而非强制 ".txt"
        // makeOutputURL 会自动加 ".txt" 扩展名（suffix: "_text"）
        let out = try context.makeOutputURL(suffix: "_text", extension: "txt")

        var args = [input.path, out.path]
        if let range = context.job.parameters.pageRange, let end = range.end {
            args = ["-f", String(range.start), "-l", String(end), input.path, out.path]
        }

        await JobOrchestrator.shared.updateProgress(id: context.job.id, progress: 0.3)
        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args)
        await JobOrchestrator.shared.updateProgress(id: context.job.id, progress: 0.9)

        guard FileManager.default.fileExists(atPath: out.path) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }
}