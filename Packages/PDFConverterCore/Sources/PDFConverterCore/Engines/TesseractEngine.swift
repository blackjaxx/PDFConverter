import Foundation

public struct TesseractEngine: ConversionEngine {
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
        let langs = context.job.parameters.ocrLanguages.joined(separator: "+")
        let outBase = context.workDirectory.appendingPathComponent("ocr_output")
        let out = (context.job.outputDirectory ?? input.deletingLastPathComponent())
            .appendingPathComponent(input.deletingPathExtension().lastPathComponent + "_ocr.pdf")

        let args = [input.path, outBase.path, "-l", langs, "pdf"]
        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args, currentDirectory: context.workDirectory)

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
