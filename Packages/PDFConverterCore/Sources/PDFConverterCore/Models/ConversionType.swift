import Foundation

/// All supported conversion kinds. New cases can be added without changing orchestrator logic.
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
}

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

    public var id: String { rawValue }

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
        }
    }

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
        }
    }

    public var isAvailableInMVP: Bool {
        switch self {
        case .pdfToPNG, .pdfToJPEG, .pngToPDF, .jpegToPDF, .mergePDF, .splitPDF, .rotatePDF,
             .pdfToText, .compressPDF, .wordToPDF, .excelToPDF, .pptToPDF, .ocrSearchablePDF:
            return true
        default:
            return false
        }
    }
}
