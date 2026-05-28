/// PDFConverterCore 是整个 PDF 转换引擎的核心 Package。
///
/// 它提供了一套可插拔的转换引擎架构，支持 PDF 与图片、Office 文档、
/// 文本等多种格式之间的互转，以及合并、拆分、加密、OCR、AI 摘要等高级功能。
///
/// 设计理念：
/// - 所有转换操作通过统一的 ``ConversionEngine`` 协议接入，新增引擎无需修改核心逻辑。
/// - 任务调度由 ``JobOrchestrator`` 管理，使用 Swift Actor 保证线程安全。
/// - CLI 工具（Poppler、qpdf、Ghostscript 等）通过 ``ToolLocator`` 统一查找，
///   优先使用 App 内捆绑的版本，回退到系统 PATH 中的版本。
///
/// 版本号通过静态属性 `version` 对外暴露，遵循语义化版本规范。
public enum PDFConverterCore {
    /// Package 的语义化版本号，遵循 `主版本.次版本.修订号` 格式。
    public static let version = "0.1.0"
}