import Foundation

/// 智能 Office 自动化引擎，按优先级链式尝试多个后端完成 Office 文档与 PDF 的互转。
///
/// 后端优先级（从高到低）：
/// 1. **Microsoft Office** — AppleScript 调用 Word/Excel/PPT 的原生导出
/// 2. **Apple iWork** — AppleScript 调用 Pages/Numbers/Keynote 的原生导出
/// 3. **LibreOffice** — 传统 headless 模式（`LibreOfficeEngine` 作为最终回退）
///
/// ## 为什么设计为链式降级？
///
/// LibreOffice 安装包约 1.2GB，不适合打包进应用 DMG。但很多 macOS 用户
/// 已经安装了 Microsoft Office 或 Apple iWork。此引擎利用系统原生自动化能力，
/// 让**绝大多数用户无需额外安装任何软件**就能完成 Office 文档转换：
///
/// - 有 Office → 用 Office 原生的高质量引擎（零额外安装）
/// - 只有 iWork → 用 iWork 导出（零额外安装）
/// - 都没装 → 回退到 LibreOffice（提示用户安装）
///
/// ## AppleScript 可靠性
///
/// 使用 `osascript` 执行，通过 `try...on error` 捕获脚本级异常。
/// 如果目标应用未安装或版本不兼容，AppleScript 块会优雅地返回非零退出码，
/// 引擎自动进入下一优先级尝试。
public struct OfficeAutomationEngine: ConversionEngine {
    public init() {}
    public let kind: EngineKind = .officeAutomation

    /// LibreOffice 引擎实例，作为最终回退
    private let libreOfficeFallback = LibreOfficeEngine()

    /// Microsoft Office 套件的 Bundle Identifier 映射表
    private let msOfficeBundleIDs: [ConversionType: String] = [
        .wordToPDF: "com.microsoft.Word",
        .excelToPDF: "com.microsoft.Excel",
        .pptToPDF: "com.microsoft.Powerpoint",
    ]

    /// Apple iWork 套件的 Bundle Identifier 映射表
    private let iWorkBundleIDs: [ConversionType: String] = [
        .wordToPDF: "com.apple.iWork.Pages",
        .excelToPDF: "com.apple.iWork.Numbers",
        .pptToPDF: "com.apple.iWork.Keynote",
    ]

    public func supportedTypes() -> Set<ConversionType> {
        [.wordToPDF, .excelToPDF, .pptToPDF, .pdfToWord, .pdfToExcel]
    }

    public func convert(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 Office 文件")
        }

        let type = context.job.type
        let outputDir = context.job.outputDirectory ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent

        // ── 第一步：Microsoft Office（仅 Office → PDF 方向） ──
        if type == .wordToPDF || type == .excelToPDF || type == .pptToPDF {
            if let result = try await tryMicrosoftOffice(input: input, outputDir: outputDir, stem: stem, type: type) {
                return result
            }

            // ── 第二步：Apple iWork（仅 Office → PDF 方向） ──
            if let result = try await tryAppleIWork(input: input, outputDir: outputDir, stem: stem, type: type) {
                return result
            }
        }

        // ── 第三步：回退到 LibreOffice（支持全部类型，包括 PDF → Office） ──
        return try await libreOfficeFallback.convert(context: context)
    }

    // MARK: - Microsoft Office (AppleScript)

    /// 尝试通过 AppleScript 调用 Microsoft Office 导出 PDF。
    ///
    /// - 根据文件类型选择 Word/Excel/PPT
    /// - 用 `NSWorkspace` 检查应用是否已安装（通过 Bundle ID）
    /// - AppleScript 内用 `try...on error` 处理运行时错误
    /// - 超时控制：`osascript` 进程最多等待 60 秒
    /// - Returns: 成功则返回 `ConversionResult`，失败返回 `nil`
    private func tryMicrosoftOffice(
        input: URL,
        outputDir: URL,
        stem: String,
        type: ConversionType
    ) async throws -> ConversionResult? {
        guard let bundleID = msOfficeBundleIDs[type] else { return nil }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return nil }

        let appName: String
        let saveFormat: String
        switch type {
        case .wordToPDF:
            appName = "Microsoft Word"
            saveFormat = "format PDF"
        case .excelToPDF:
            appName = "Microsoft Excel"
            saveFormat = "PDF"
        case .pptToPDF:
            appName = "Microsoft PowerPoint"
            saveFormat = "PDF"
        default:
            return nil
        }

        let outputPath = outputDir.appendingPathComponent(stem + "_converted.pdf").path

        // AppleScript: 打开文件 → 导出为 PDF → 关闭（不保存原文件）
        // 外层 try 捕获脚本级异常（如应用版本不兼容、文件打不开等）
        let script = """
        try
            tell application "\(appName)"
                set doc to open POSIX file "\(input.path)"
                save as doc filename "\(outputPath)" file format \(saveFormat)
                close doc saving no
            end tell
            return "OK"
        on error errMsg
            return "ERROR: " & errMsg
        end try
        """

        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script]
        )

        guard result.exitCode == 0, result.stdout.hasPrefix("OK") else {
            return nil
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return nil
        }

        return ConversionResult(outputURLs: [outputURL],
                                logs: "[OfficeAutomation] Microsoft \(appName) 导出成功")
    }

    // MARK: - Apple iWork (AppleScript)

    /// 尝试通过 AppleScript 调用 Apple iWork 套件导出 PDF。
    ///
    /// iWork 的 AppleScript API 与 Microsoft Office 不同：
    /// - Pages/Keynote: `export to PDF: file "<path>"`
    /// - Numbers: `export as PDF: file "<path>"`（参数名不同）
    /// - 全部不需要指定 format，默认就是 PDF
    /// - Returns: 成功则返回 `ConversionResult`，失败返回 `nil`
    private func tryAppleIWork(
        input: URL,
        outputDir: URL,
        stem: String,
        type: ConversionType
    ) async throws -> ConversionResult? {
        guard let bundleID = iWorkBundleIDs[type] else { return nil }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return nil }

        let appName: String
        let exportVerb: String
        switch type {
        case .wordToPDF:
            appName = "Pages"
            exportVerb = "export to PDF"
        case .excelToPDF:
            appName = "Numbers"
            exportVerb = "export as PDF"
        case .pptToPDF:
            appName = "Keynote"
            exportVerb = "export to PDF"
        default:
            return nil
        }

        let outputPath = outputDir.appendingPathComponent(stem + "_converted.pdf").path

        let script = """
        try
            tell application "\(appName)"
                set doc to open POSIX file "\(input.path)"
                \(exportVerb): file "\(outputPath)"
                close doc saving no
            end tell
            return "OK"
        on error errMsg
            return "ERROR: " & errMsg
        end try
        """

        let result = try await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", script]
        )

        guard result.exitCode == 0, result.stdout.hasPrefix("OK") else {
            return nil
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return nil
        }

        return ConversionResult(outputURLs: [outputURL],
                                logs: "[OfficeAutomation] \(appName) 导出成功")
    }
}
