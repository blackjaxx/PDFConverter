import Foundation

/// 引擎类型标识，一个 ``ConversionEngine`` 对应一个 kind。
///
/// 这个枚举的作用是为每个引擎提供一个唯一的身份标识，使得：
/// - ``EngineRegistry.types(for:)`` 可以根据 kind 反向查找该引擎支持的所有转换类型
/// - 日志和调试时可以快速定位到具体是哪个引擎在工作
/// - 新增引擎只需添加一个 case，UI 和注册中心无需修改
///
/// 注意：`EngineKind` 描述的是"使用哪种后端技术"，而非"支持哪些转换类型"。
/// 例如 `pdfKit` 引擎可以处理 `pngToPDF`、`rotatePDF`、`mergePDF` 等多种类型。
public enum EngineKind: String, CaseIterable, Codable, Sendable {
    /// macOS 原生 PDFKit 框架，无需额外 CLI 工具
    case pdfKit
    /// Poppler 工具集（pdftoppm、pdftotext），处理 PDF 到图片/文本的转换
    case poppler
    /// qpdf 工具，处理 PDF 拆分、加密和解密
    case qpdf
    /// Ghostscript，通过 pdfwrite 设备进行 PDF 压缩
    case ghostscript
    /// LibreOffice headless 模式，处理 Office 文档与 PDF 的互转
    case libreOffice
    /// Tesseract OCR 引擎，将图片 PDF 转为可搜索 PDF
    case tesseract
    /// WebKit，用于 HTML 到 PDF 的转换
    case webKit
    /// DeepSeek AI API，提供摘要、翻译、Markdown 转换等 AI 功能
    case deepSeek
}

/// 封装一个捆绑的 CLI 工具的信息。
///
/// 每个 `BundledTool` 描述了一个可执行文件在 App Bundle 中的位置和所属引擎。
/// ``ToolLocator`` 使用这些信息去 `Resources/tools` 目录下查找对应的可执行文件。
public struct BundledTool: Sendable {
    /// 工具的可执行文件名（例如 `"pdftoppm"`、`"gs"`）
    public let name: String
    /// 工具在 `Resources/tools` 下的相对路径（例如 `"poppler/pdftoppm"`）
    public let relativePath: String
    /// 该工具所属的引擎种类，用于按引擎维度查询工具可用性
    public let engine: EngineKind

    public init(name: String, relativePath: String, engine: EngineKind) {
        self.name = name
        self.relativePath = relativePath
        self.engine = engine
    }
}

/// 所有捆绑工具的清单，是 ``ToolLocator`` 查找工具的索引表。
///
/// 当调用 `Scripts/bundle-tools.sh` 脚本时，每个引擎的可执行文件会被复制
/// 到 `Resources/tools/<engine>/` 目录下。这里的清单必须与脚本打包的结果保持一致。
///
/// 为什么不直接从文件系统扫描？
/// - 清单式管理更可控：明确知道需要哪些工具，避免打包了无用文件
/// - 性能更好：不需要遍历文件系统
/// - 与 ``ToolLocator.availabilityReport()`` 配合，可以批量检查工具是否就绪
public enum BundledToolsCatalog {
    /// 所有捆绑工具的静态列表
    public static let all: [BundledTool] = [
        BundledTool(name: "pdftoppm", relativePath: "poppler/pdftoppm", engine: .poppler),
        BundledTool(name: "pdftotext", relativePath: "poppler/pdftotext", engine: .poppler),
        BundledTool(name: "qpdf", relativePath: "qpdf/qpdf", engine: .qpdf),
        BundledTool(name: "gs", relativePath: "ghostscript/gs", engine: .ghostscript),
        BundledTool(name: "soffice", relativePath: "libreoffice/soffice", engine: .libreOffice),
        BundledTool(name: "tesseract", relativePath: "tesseract/tesseract", engine: .tesseract)
    ]
}