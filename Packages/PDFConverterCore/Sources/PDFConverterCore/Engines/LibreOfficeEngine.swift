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
    public let kind: EngineKind = .libreOffice

    private let soffice = BundledTool(name: "soffice", relativePath: "libreoffice/soffice", engine: .libreOffice)

    public func supportedTypes() -> Set<ConversionType> {
        [.wordToPDF, .excelToPDF, .pptToPDF, .pdfToWord, .pdfToExcel]
    }

    public func convert(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 Office 文件")
        }
        let tool = try ToolLocator.shared.require(soffice)
        let outDir = context.job.outputDirectory ?? input.deletingLastPathComponent()

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

        // LibreOffice headless 参数说明：
        // --headless                     → 不启动 GUI
        // -env:UserInstallation=file:// → 指定独立的用户配置目录
        // --convert-to <filter>          → 目标格式（pdf/docx/xlsx）
        // --outdir <dir>                 → 输出目录
        let args = [
            "--headless",
            "-env:UserInstallation=file://\(profileDir.path)",
            "--convert-to", filter,
            "--outdir", outDir.path,
            input.path
        ]

        _ = try await ProcessRunner.runChecked(
            executable: tool,
            arguments: args,
            environment: ["HOME": context.workDirectory.path]
        )

        let expectedExt = filter == "pdf" ? "pdf" : filter
        let expectedName = input.deletingPathExtension().lastPathComponent + ".\(expectedExt)"
        let out = outDir.appendingPathComponent(expectedName)

        guard FileManager.default.fileExists(atPath: out.path) else {
            // 有时候输出文件名与预期不一致，此时按修改时间取最新的同扩展名文件
            let generated = try FileManager.default.contentsOfDirectory(
                at: outDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
            .filter { $0.pathExtension == expectedExt }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            guard let latest = generated.first else {
                throw ConversionError.outputMissing(expectedName)
            }
            return ConversionResult(outputURLs: [latest])
        }
        return ConversionResult(outputURLs: [out])
    }
}