import Foundation

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

        let profileDir = context.workDirectory.appendingPathComponent("lo_profile", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

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
