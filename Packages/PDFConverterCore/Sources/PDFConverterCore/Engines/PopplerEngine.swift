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
    public let kind: EngineKind = .poppler

    /// pdftoppm 工具的 BundledTool 描述，用于 ``ToolLocator`` 查找
    private let pdftoppm = BundledTool(name: "pdftoppm", relativePath: "poppler/pdftoppm", engine: .poppler)
    /// pdftotext 工具的 BundledTool 描述
    private let pdftotext = BundledTool(name: "pdftotext", relativePath: "poppler/pdftotext", engine: .poppler)

    public init() {}

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
    /// 输出文件命名格式：`page-1.png`、`page-2.png` 等。
    /// 生成的文件从临时工作目录移动到目标输出目录。
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

        // pdftoppm 的 output prefix：生成的文件名为 `page-1.png`、`page-2.png` 等
        let prefix = context.workDirectory.appendingPathComponent("page").path
        var args = ["-\(format)", "-r", dpi, input.path, prefix]

        // 如果指定了页码范围，插入 -f 和 -l 参数
        // 注意插入位置必须正确：pdftoppm 的参数顺序是 [options] input output-prefix
        if let range = context.job.parameters.pageRange {
            args.insert(contentsOf: ["-f", String(range.start)], at: 0)
            if let end = range.end {
                args.insert(contentsOf: ["-l", String(end)], at: 2)
            }
        }

        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args, currentDirectory: context.workDirectory)

        // 扫描临时目录中的输出文件，按文件名排序
        let files = try FileManager.default.contentsOfDirectory(at: context.workDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == ext }
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
    private func pdfToText(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF")
        }
        let tool = try ToolLocator.shared.require(pdftotext)
        let out = try context.makeOutputURL(suffix: "", extension: "txt")

        var args = [input.path, out.path]
        if let range = context.job.parameters.pageRange, let end = range.end {
            args = ["-f", String(range.start), "-l", String(end), input.path, out.path]
        }

        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args)
        guard FileManager.default.fileExists(atPath: out.path) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }
}