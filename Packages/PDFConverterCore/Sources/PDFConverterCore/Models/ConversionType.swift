import Foundation

/// 转换操作的大分类维度，与 UI 侧边栏的分组一一对应。
///
/// 在 UI 中，用户首先看到的是这些分类（如"PDF → 图片"、"页面"、"安全"等），
/// 点击分类后再展开具体的 ``ConversionType``。新增类型时只需添加新的 case，
/// 并在 ``ConversionType.category`` 中建立映射关系即可。
///
/// 为什么需要两层枚举？
/// - ``ConversionCategory`` 负责 UI 分组，让用户按功能区域浏览
/// - ``ConversionType`` 负责具体的转换逻辑，引擎根据 type 决定调用哪个后端方法
/// - 这种设计使得 UI 层和引擎层解耦，UI 只需关心分类，引擎只需关心具体类型
public enum ConversionCategory: String, CaseIterable, Codable, Sendable {
    case pdfToImage
    case imageToPDF
    case pdfToText
    case officeToPDF
    case pdfToOffice
    case htmlToPDF
    case compress
    case merge
    case split
    case rotate
    case watermark
    case encrypt
    case decrypt
    case ocr
    case ai

    /// 分类在 UI 中的显示名称，为所有分类提供统一的本地化文案入口。
    public var displayName: String {
        switch self {
        case .pdfToImage: return "PDF → 图片"
        case .imageToPDF: return "图片 → PDF"
        case .pdfToText: return "PDF → 文本"
        case .officeToPDF: return "Office → PDF"
        case .pdfToOffice: return "PDF → Office"
        case .htmlToPDF: return "网页"
        case .compress: return "优化"
        case .merge: return "页面"
        case .split: return "页面"
        case .rotate: return "编辑"
        case .watermark: return "编辑"
        case .encrypt: return "安全"
        case .decrypt: return "安全"
        case .ocr: return "OCR"
        case .ai: return "AI (DeepSeek)"
        }
    }
}

/// 所有支持的转换类型枚举，每个 case 对应一个具体的转换操作。
///
/// 这是整个引擎系统的"菜单"——用户选择一种类型，系统根据类型查找
/// 对应的 ``ConversionEngine``，然后执行转换。
///
/// 设计要点：
/// - 实现 `Identifiable`，方便在 SwiftUI `List` 等视图中使用
/// - 实现 `Codable`，支持任务持久化和恢复
/// - 通过 `category` 属性映射到 ``ConversionCategory``，实现 UI 分组
/// - `isAvailableInMVP` 控制当前版本的功能可见性，未实现的功能设为 `false`
public enum ConversionType: String, CaseIterable, Codable, Identifiable, Sendable {
    case pdfToPNG
    case pdfToJPEG
    case pdfToTIFF
    case pngToPDF
    case jpegToPDF
    case pdfToText
    case wordToPDF
    case excelToPDF
    case pptToPDF
    case pdfToWord
    case pdfToExcel
    case htmlToPDF
    case compressPDF
    case mergePDF
    case splitPDF
    case rotatePDF
    case watermarkPDF
    case encryptPDF
    case decryptPDF
    case ocrSearchablePDF
    case pdfAISummary
    case pdfAITranslate
    case pdfAIToMarkdown

    public var id: String { rawValue }

    /// 将该类型映射到其所属的 ``ConversionCategory``，是 UI 分组和过滤的依据。
    ///
    /// 例如 `.pdfToPNG`、`.pdfToJPEG`、`.pdfToTIFF` 都归入 `.pdfToImage` 分类，
    /// 在 UI 中表现为 "PDF → 图片" 分组下的三个选项。
    public var category: ConversionCategory {
        switch self {
        case .pdfToPNG, .pdfToJPEG, .pdfToTIFF: return .pdfToImage
        case .pngToPDF, .jpegToPDF: return .imageToPDF
        case .pdfToText: return .pdfToText
        case .wordToPDF, .excelToPDF, .pptToPDF: return .officeToPDF
        case .pdfToWord, .pdfToExcel: return .pdfToOffice
        case .htmlToPDF: return .htmlToPDF
        case .compressPDF: return .compress
        case .mergePDF: return .merge
        case .splitPDF: return .split
        case .rotatePDF: return .rotate
        case .watermarkPDF: return .watermark
        case .encryptPDF: return .encrypt
        case .decryptPDF: return .decrypt
        case .ocrSearchablePDF: return .ocr
        case .pdfAISummary, .pdfAITranslate, .pdfAIToMarkdown: return .ai
        }
    }

    /// 类型在 UI 中的显示名称。
    public var displayName: String {
        switch self {
        case .pdfToPNG: return "PDF → PNG"
        case .pdfToJPEG: return "PDF → JPEG"
        case .pdfToTIFF: return "PDF → TIFF"
        case .pngToPDF: return "PNG → PDF"
        case .jpegToPDF: return "JPEG → PDF"
        case .pdfToText: return "PDF → 文本"
        case .wordToPDF: return "Word → PDF"
        case .excelToPDF: return "Excel → PDF"
        case .pptToPDF: return "PPT → PDF"
        case .pdfToWord: return "PDF → Word"
        case .pdfToExcel: return "PDF → Excel"
        case .htmlToPDF: return "HTML → PDF"
        case .compressPDF: return "压缩 PDF"
        case .mergePDF: return "合并 PDF"
        case .splitPDF: return "拆分 PDF"
        case .rotatePDF: return "旋转页面"
        case .watermarkPDF: return "添加水印"
        case .encryptPDF: return "加密 PDF"
        case .decryptPDF: return "解密 PDF"
        case .ocrSearchablePDF: return "OCR 可搜索 PDF"
        case .pdfAISummary: return "AI 摘要 (DeepSeek)"
        case .pdfAITranslate: return "AI 翻译 (DeepSeek)"
        case .pdfAIToMarkdown: return "AI → Markdown (DeepSeek)"
        }
    }

    /// 该类型是否需要网络连接。
    /// 目前只有 AI 相关功能（调用 DeepSeek API）需要网络，其他均为本地操作。
    /// UI 层可根据这个属性显示网络依赖提示或离线模式警告。
    public var requiresNetwork: Bool {
        category == .ai
    }

    /// 该类型在当前 MVP（最小可行产品）版本中是否可用。
    ///
    /// 用于控制功能的逐步发布——已实现并测试通过的类型设为 `true`，
    /// 尚未完成或需要后续版本支持的类型设为 `false`。
    /// UI 层根据这个属性决定是否显示该功能入口或将其置灰。
    ///
    /// 修复：`.pdfToWord` 和 `.pdfToExcel` 已实现（OfficeAutomationEngine +
    /// LibreOffice 回退），之前未加入列表是历史遗漏。现在补全，
    /// 否则这两个类型会被 SidebarView 标记为「预览」并禁用。
    public var isAvailableInMVP: Bool {
        switch self {
        case .pdfToPNG, .pdfToJPEG, .pngToPDF, .jpegToPDF, .mergePDF, .splitPDF, .rotatePDF,
             .pdfToText, .compressPDF, .wordToPDF, .excelToPDF, .pptToPDF, .ocrSearchablePDF,
             .pdfToWord, .pdfToExcel,
             .pdfAISummary, .pdfAITranslate, .pdfAIToMarkdown:
            return true
        default:
            return false
        }
    }
}
