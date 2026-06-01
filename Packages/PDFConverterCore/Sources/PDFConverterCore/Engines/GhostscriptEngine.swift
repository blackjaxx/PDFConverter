import Foundation

/// 基于 Ghostscript 的转换引擎，专门处理 PDF 压缩。
///
/// Ghostscript 是一个强大的 PostScript 和 PDF 解释器，通过它的 `pdfwrite` 设备
/// 可以将 PDF 重新编码为更紧凑的格式，在保持可读性的前提下显著减小文件体积。
///
/// ## 压缩级别说明
/// Ghostscript 提供了 5 个预设压缩级别（通过 `-dPDFSETTINGS` 参数指定）：
///
/// | 级别       | 典型文件大小 | 适用场景           |
/// |-----------|------------|-------------------|
/// | `screen`  | 最小       | 屏幕查看（最低质量）   |
/// | `ebook`   | 中等偏小    | 电子书阅读（**默认**） |
/// | `printer` | 中等       | 打印输出            |
/// | `prepress`| 较大       | 印刷前制版（最高质量）  |
/// | `default` | 原始大小    | 几乎不压缩           |
///
/// 默认使用 `ebook` 级别，是文件大小和视觉质量的最佳平衡点。
///
/// ## 工作原理
/// Ghostscript 的 `pdfwrite` 设备不是简单的"压缩"，而是**重新生成** PDF——
/// 它解析输入 PDF，然后用优化后的方式重新编码。这个过程可以：
/// - 移除冗余的字体数据
/// - 重新采样图片到更低分辨率
/// - 移除未使用的对象
/// - 优化交叉引用表
///
/// 因此，压缩后的 PDF 在视觉上与原始几乎相同，但文件大小可以缩小 50%~90%。
public struct GhostscriptEngine: ConversionEngine {
    public let kind: EngineKind = .ghostscript

    private let gs = BundledTool(name: "gs", relativePath: "ghostscript/gs", engine: .ghostscript)

    public init() {}

    public func supportedTypes() -> Set<ConversionType> {
        [.compressPDF]
    }

    public func convert(context: ConversionContext) async throws -> ConversionResult {
        guard context.job.type == .compressPDF else {
            throw ConversionError.unsupportedType(context.job.type)
        }
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF")
        }
        let tool = try ToolLocator.shared.require(gs)
        let level = context.job.parameters.compressionLevel
        let out = try context.makeOutputURL(suffix: "_compressed", extension: "pdf")

        // Ghostscript pdfwrite 设备的核心参数：
        // -sDEVICE=pdfwrite     → 使用 PDF 写入设备
        // -dCompatibilityLevel  → PDF 兼容性级别（1.4 保证广泛兼容）
        // -dPDFSETTINGS         → 压缩预设级别
        // -dNOPAUSE             → 处理完所有页面后不暂停
        // -dQUIET               → 抑制非错误信息的输出
        // -dBATCH               → 处理完后退出（不进入交互模式）
        let args = [
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-dPDFSETTINGS=/\(level)",
            "-dNOPAUSE",
            "-dQUIET",
            "-dBATCH",
            "-sOutputFile=\(out.path)",
            input.path
        ]

        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args)
        return ConversionResult(outputURLs: [out])
    }
}