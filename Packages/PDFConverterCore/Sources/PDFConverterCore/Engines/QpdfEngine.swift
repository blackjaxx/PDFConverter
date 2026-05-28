import Foundation

/// 基于 qpdf 工具的转换引擎，处理 PDF 拆分、加密和解密。
///
/// qpdf 是一个专业的 PDF 内容保留变换工具（Content-Preserving Transformations），
/// 它的核心优势在于：
/// - **保留 PDF 结构**：拆分和加密操作不会重新编码页面内容，因此输出质量无损
/// - **256-bit AES 加密**：使用行业标准级别的加密算法保护 PDF 文件
/// - **高性能**：操作是结构级的（不渲染页面），速度远快于基于渲染的工具
///
/// ## qpdf vs PDFKit
/// PDFKit 也可以做部分拆分操作（逐页复制），但 qpdf 直接操作 PDF 内部结构，
/// 处理速度和文件大小都更优。加密功能 PDFKit 不支持，必须用 qpdf。
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

    /// 使用 `--split-pages` 参数将 PDF 逐页拆分为多个独立的 PDF 文件。
    ///
    /// qpdf 的 `--split-pages` 会为每页生成一个独立的 PDF 文件，命名格式为
    /// `文件名_split-1.pdf`、`文件名_split-2.pdf` 等。
    ///
    /// - Note: 输出文件数量等于输入 PDF 的页数
    private func split(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF")
        }
        let tool = try ToolLocator.shared.require(qpdf)
        let out = try context.makeOutputURL(suffix: "_split", extension: "pdf")

        let args = ["--split-pages", input.path, out.path]
        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args)

        // qpdf --split-pages 生成的文件以输出文件名为前缀
        // 例如 output_split.pdf → output_split-1.pdf, output_split-2.pdf
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

    /// 对 PDF 进行加密（256-bit AES）或解密操作。
    ///
    /// ## 加密参数
    /// ```
    /// qpdf --encrypt <user-password> <owner-password> 256 -- input.pdf output.pdf
    /// ```
    /// - `user-password`：用户打开 PDF 时需要输入的密码
    /// - `owner-password`：所有者密码（用于权限控制，此处设为相同值简化 UI）
    /// - `256`：使用 256-bit AES 加密
    ///
    /// ## 解密参数
    /// ```
    /// qpdf --password=<password> --decrypt input.pdf output.pdf
    /// ```
    ///
    /// - Parameters:
    ///   - context: 转换上下文
    ///   - decrypt: `true` 表示解密，`false` 表示加密
    private func encrypt(context: ConversionContext, decrypt: Bool) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF")
        }
        guard let password = context.job.parameters.password, !password.isEmpty else {
            throw ConversionError.invalidInput("请设置密码")
        }
        let tool = try ToolLocator.shared.require(qpdf)
        let suffix = decrypt ? "_decrypted" : "_encrypted"
        let out = try context.makeOutputURL(suffix: suffix, extension: "pdf")

        let args: [String]
        if decrypt {
            // 解密：提供原密码
            args = ["--password=\(password)", "--decrypt", input.path, out.path]
        } else {
            // 加密：user-password 和 owner-password 设为相同值，简化用户操作
            args = ["--encrypt", password, password, "256", "--", input.path, out.path]
        }

        _ = try await ProcessRunner.runChecked(executable: tool, arguments: args)
        return ConversionResult(outputURLs: [out])
    }
}