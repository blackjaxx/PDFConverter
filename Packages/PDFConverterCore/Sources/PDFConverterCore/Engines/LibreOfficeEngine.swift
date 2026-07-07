import Foundation

/// 基于 LibreOffice headless 模式的转换引擎，处理 Office 文档与 PDF 的互转。
///
/// LibreOffice 是目前最强大的开源办公套件，它的 `--headless` 模式允许在没有 GUI 的
/// 环境下运行文档转换。这个引擎利用该特性实现：
/// - Word (.docx) → PDF
/// - Excel (.xlsx) → PDF
/// - PowerPoint (.pptx) → PDF
/// - PDF → Word (.docx)
/// - PDF → Excel (.xlsx)
///
/// ## 为什么需要独立的用户配置目录（profileDir）？
///
/// LibreOffice 正常情况下依赖一个用户配置目录（通常位于 `~/.config/libreoffice`），
/// 其中存储字体缓存、扩展、最近文件列表等。如果多个 LibreOffice 实例共用同一个
/// 配置目录，可能会发生文件锁冲突导致转换失败。
///
/// 解决方案：为每次转换创建独立的配置目录，通过 `-env:UserInstallation` 参数指定。
/// 这个目录在临时工作目录下，任务完成后由 ``JobOrchestrator`` 自动清理。
///
/// ## 环境变量 `HOME`
///
/// 设置 `HOME` 环境变量指向工作目录，是为了确保 LibreOffice 在 headless 模式下
/// 找到正确的配置文件路径。这对于在沙盒环境中运行尤其重要。
public struct LibreOfficeEngine: ConversionEngine {
    public init() {}
    public let kind: EngineKind = .libreOffice

    private let soffice = BundledTool(name: "soffice", relativePath: "libreoffice/soffice", engine: .libreOffice)

    public func supportedTypes() -> Set<ConversionType> {
        [.wordToPDF, .excelToPDF, .pptToPDF, .pdfToWord, .pdfToExcel]
    public func convert(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 Office 文件")
        }
        let tool = try ToolLocator.shared.require(soffice)
        let outDirInput = context.job.outputDirectory ?? input.deletingLastPathComponent()

        // 根据转换类型决定目标格式（LibreOffice 的 --convert-to 参数）
        let filter: String
        switch context.job.type {
        case .wordToPDF, .excelToPDF, .pptToPDF:
            filter = "pdf"
        case .pdfToWord:
            filter = "docx"
        case .pdfToExcel:
            filter = "xlsx"
        default:
            throw ConversionError.unsupportedType(context.job.type)
        }

        // 创建独立的 LibreOffice 用户配置文件目录，避免多任务并发时的锁冲突
        let profileDir = context.workDirectory.appendingPathComponent("lo_profile", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        // 使用单独的干净输出子目录，避免和 outDir 中既有文件混淆。
        // LibreOffice 的 --convert-to 没有提供精确输出文件名控制，
        // 用隔离目录后可直接按扩展名扫描，无需依赖修改时间。
        let isolatedOutDir = context.workDirectory.appendingPathComponent("lo_output", isDirectory: true)
        try FileManager.default.createDirectory(at: isolatedOutDir, withIntermediateDirectories: true)

        // LibreOffice headless 参数说明：
        // --headless                     → 不启动 GUI
        // -env:UserInstallation=file:// → 指定独立的用户配置目录
        // --convert-to <filter>          → 目标格式（pdf/docx/xlsx）
        // --outdir <dir>                 → 输出目录
        let args = [
            "--headless",
            "-env:UserInstallation=file://\(profileDir.path)",
            "--convert-to",
            filter,
            "--outdir",
            isolatedOutDir.path,
            input.path
        ]

        _ = try await ProcessRunner.runChecked(
            executable: tool,
            arguments: args,
            environment: ["HOME": context.workDirectory.path]
        )

        let expectedExt = filter == "pdf" ? "pdf" : filter
        let expectedStem = input.deletingPathExtension().lastPathComponent
        let outputs = try FileManager.default.contentsOfDirectory(at: isolatedOutDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == expectedExt }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !outputs.isEmpty else {
            throw ConversionError.outputMissing("\(expectedStem).\(expectedExt)")
        }

        let finalOutDir = outDirInput
        var finalURLs: [URL] = []
        for generated in outputs {
            let dest = finalOutDir.appendingPathComponent(generated.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: generated, to: dest)
            finalURLs.append(dest)
        }

        return ConversionResult(outputURLs: finalURLs)
    }
}