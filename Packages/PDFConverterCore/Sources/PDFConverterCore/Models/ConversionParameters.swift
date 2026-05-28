import Foundation

/// 页码范围模型，用于指定转换操作从第几页到第几页。
///
/// `start` 是从 1 开始的起始页码（符合用户习惯），`end` 为 nil 时
/// 表示从起始页一直处理到最后一页。
///
/// 使用场景：
/// - PDF 转图片时指定只导出某些页
/// - PDF 转文本时只提取部分页面的内容
/// - 传递给 `pdftoppm` 的 `-f` / `-l` 参数
public struct PageRange: Codable, Sendable, Equatable {
    /// 起始页码（从 1 开始）
    public var start: Int
    /// 结束页码（包含），为 nil 表示处理到文档末尾
    public var end: Int?

    public init(start: Int = 1, end: Int? = nil) {
        self.start = start
        self.end = end
    }

    /// 用户可读的显示字符串，例如 "1-5" 或 "3"
    public var displayString: String {
        if let end {
            return "\(start)-\(end)"
        }
        return "\(start)"
    }
}

/// 所有转换参数的集合，聚合了所有类型转换可能用到的配置项。
///
/// 为什么用一个大结构体而不是每种转换类型单独定义参数？
/// - 简化序列化：一个 `ConversionParameters` 直接 `Codable`，无需多态处理
/// - 简化传递：`ConversionJob` 只需要持有一个参数对象，不需要关心类型
/// - 互斥使用：不同的转换类型只用到参数的一个子集（如压缩只用 `compressionLevel`），
///   未用到的字段附带默认值，不会产生实际影响
///
/// 所有字段都有合理的默认值，用户不修改时也能正常工作。
public struct ConversionParameters: Codable, Sendable {
    /// 图片输出的分辨率（DPI，Dots Per Inch）。
    /// 默认 150 DPI 是清晰度与文件大小的平衡点；需要高清输出可调到 300。
    public var dpi: Int
    /// JPEG 输出质量（0.0 ~ 1.0），默认 0.85。
    /// 仅对 `.pdfToJPEG` 类型生效。
    public var jpegQuality: Double
    /// 限定转换的页码范围，nil 表示处理全部页面
    public var pageRange: PageRange?
    /// 旋转角度（仅支持 90 的倍数，如 90、180、270），用于 `.rotatePDF`
    public var rotationDegrees: Int
    /// PDF 加密/解密用的密码。
    /// 加密时作为新密码，解密时需要提供原密码。
    public var password: String?
    /// OCR 识别的语言列表，例如 `["chi_sim", "eng"]` 表示简体中文 + 英文。
    /// 传入多个语言会以 `+` 连接后传给 Tesseract。
    public var ocrLanguages: [String]
    /// Ghostscript 压缩级别，可选值：`screen`、`ebook`、`printer`、`prepress`、`default`。
    /// `ebook` 提供了中等压缩质量和文件大小，适合电子阅读。
    public var compressionLevel: String
    /// 水印文字内容，用于 `.watermarkPDF` 类型
    public var watermarkText: String?
    /// AI 翻译的目标语言描述（如 "简体中文"、"English"），用于 `.pdfAITranslate`。
    public var aiTargetLanguage: String
    /// 发送给 AI 的 PDF 文本最大字符数，默认 12000。
    /// 截断是为了控制 API 调用的 token 消耗和响应时间。
    public var aiMaxInputChars: Int
    /// 附加的自定义 AI 指令，会追加到 prompt 末尾。
    /// 例如 "请用表格形式呈现"、"突出关键数据" 等。
    public var aiCustomInstruction: String?

    public init(
        dpi: Int = 150,
        jpegQuality: Double = 0.85,
        pageRange: PageRange? = nil,
        rotationDegrees: Int = 90,
        password: String? = nil,
        ocrLanguages: [String] = ["chi_sim", "eng"],
        compressionLevel: String = "ebook",
        watermarkText: String? = nil,
        aiTargetLanguage: String = "简体中文",
        aiMaxInputChars: Int = 12_000,
        aiCustomInstruction: String? = nil
    ) {
        self.dpi = dpi
        self.jpegQuality = jpegQuality
        self.pageRange = pageRange
        self.rotationDegrees = rotationDegrees
        self.password = password
        self.ocrLanguages = ocrLanguages
        self.compressionLevel = compressionLevel
        self.watermarkText = watermarkText
        self.aiTargetLanguage = aiTargetLanguage
        self.aiMaxInputChars = aiMaxInputChars
        self.aiCustomInstruction = aiCustomInstruction
    }
}