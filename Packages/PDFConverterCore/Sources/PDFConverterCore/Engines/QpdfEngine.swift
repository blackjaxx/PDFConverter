import Foundation

public struct QpdfEngine: ConversionEngine {
    public let kind: EngineKind = .qpdf

    private let qpdf = BundledTool(name: "qpdf", relativePath: "qpdf/qpdf", engine: .qpdf)

    public func supportedTypes() -> Set<ConversionType> {
        [.splitPDF, .encryptPDF, .decryptPDF]
    }

    public func convert(context: ConversionContext) async throws -> ConversionResult {
        switch context.job.type {
        case .splitPDF:
            return try await split(context: context)
        case .encryptPDF:
            return try await encrypt(context: context, decrypt: false)
        case .decryptPDF:
            return try await encrypt(context: context, decrypt: true)
        default:
            throw ConversionError.unsupportedType(context.job.type)
        }
    }

    private func split(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF")
        }
        let tool = try ToolLocator.shared.require(qpdf)
        let out = (context.job.outputDirectory ?? input.deletingLastPathComponent())
            .appendingPathComponent(input.deletingPathExtension().lastPathComponent + "_split.pdf")

        let args = ["--split-pages", input.path, out.path]
        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args)

        let dir = out.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let outputs = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(stem) && $0.pathExtension == "pdf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !outputs.isEmpty else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: outputs)
    }

    private func encrypt(context: ConversionContext, decrypt: Bool) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF")
        }
        guard let password = context.job.parameters.password, !password.isEmpty else {
            throw ConversionError.invalidInput("请设置密码")
        }
        let tool = try ToolLocator.shared.require(qpdf)
        let suffix = decrypt ? "_decrypted" : "_encrypted"
        let out = (context.job.outputDirectory ?? input.deletingLastPathComponent())
            .appendingPathComponent(input.deletingPathExtension().lastPathComponent + suffix + ".pdf")

        let args: [String]
        if decrypt {
            args = ["--password=\(password)", "--decrypt", input.path, out.path]
        } else {
            args = ["--encrypt", password, password, "256", "--", input.path, out.path]
        }

        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args)
        return ConversionResult(outputURLs: [out])
    }
}
