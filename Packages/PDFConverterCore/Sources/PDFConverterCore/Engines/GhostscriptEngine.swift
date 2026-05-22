import Foundation

public struct GhostscriptEngine: ConversionEngine {
    public let kind: EngineKind = .ghostscript

    private let gs = BundledTool(name: "gs", relativePath: "ghostscript/gs", engine: .ghostscript)

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
        let out = (context.job.outputDirectory ?? input.deletingLastPathComponent())
            .appendingPathComponent(input.deletingPathExtension().lastPathComponent + "_compressed.pdf")

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
