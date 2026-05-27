import Foundation

public struct PopplerEngine: ConversionEngine {
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

        let prefix = context.workDirectory.appendingPathComponent("page").path
        var args = ["-\(format)", "-r", dpi, input.path, prefix]

        if let range = context.job.parameters.pageRange {
            args.insert(contentsOf: ["-f", String(range.start)], at: 0)
            if let end = range.end {
                args.insert(contentsOf: ["-l", String(end)], at: 2)
            }
        }

        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args, currentDirectory: context.workDirectory)

        let files = try FileManager.default.contentsOfDirectory(at: context.workDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == ext }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !files.isEmpty else {
            throw ConversionError.outputMissing(ext)
        }

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
