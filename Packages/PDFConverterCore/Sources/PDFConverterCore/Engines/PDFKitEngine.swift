import Foundation
import PDFKit
import AppKit

/// 基于 macOS 原生 PDFKit 框架的转换引擎。
///
/// 这是唯一一个**不需要任何外部 CLI 工具**的引擎——它直接使用 macOS 内置的 PDFKit 框架。
/// 因此它也最稳定、启动最快，是最优先考虑使用的引擎。
///
/// 支持的操作：
/// - 图片转 PDF（PNG、JPEG → PDF）
/// - PDF 页面旋转
/// - PDF 合并
/// - 添加文字水印
///
/// ## 为什么 PDFKit 只能处理这些操作？
/// PDFKit 是一个 PDF 渲染和操作框架，它能创建和修改 PDF 文档，
/// 但不具备以下能力：
/// - 无法将 PDF 渲染为图片（这需要 `pdftoppm`）
/// - 无法压缩 PDF（这需要 Ghostscript 的 `pdfwrite` 设备）
/// - 无法进行 OCR（这需要 Tesseract）
/// - 无法处理 Office 格式（这需要 LibreOffice）
///
/// 所以 PDFKit 和其他引擎是互补关系，各自处理不同类别的转换。
public struct PDFKitEngine: ConversionEngine {
    public let kind: EngineKind = .pdfKit

    public init() {}

    public func supportedTypes() -> Set<ConversionType> {
        [.pngToPDF, .jpegToPDF, .rotatePDF, .mergePDF, .watermarkPDF]
    }

    public func convert(context: ConversionContext) async throws -> ConversionResult {
        switch context.job.type {
        case .pngToPDF, .jpegToPDF:
            return try await imageToPDF(context: context)
        case .rotatePDF:
            return try await rotatePDF(context: context)
        case .mergePDF:
            return try await mergePDF(context: context)
        case .watermarkPDF:
            return try await watermarkPDF(context: context)
        default:
            throw ConversionError.unsupportedType(context.job.type)
        }
    }

    /// 将多张图片组装成一个 PDF 文档。
    ///
    /// 图片按文件名排序后依次插入 PDF，每张图片占一页。
    /// 使用 `NSImage` 读取图片，`PDFPage(image:)` 创建 PDF 页面。
    ///
    /// - Note: 如果某张图片无法读取（例如格式损坏），会抛出 `invalidInput` 错误
    private func imageToPDF(context: ConversionContext) async throws -> ConversionResult {
        let images = context.job.inputURLs.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !images.isEmpty else {
            throw ConversionError.invalidInput("请至少选择一张图片")
        }

        let pdf = PDFDocument()
        for (index, url) in images.enumerated() {
            guard let data = try? Data(contentsOf: url),
                  let nsImage = NSImage(data: data),
                  let page = PDFPage(image: nsImage) else {
                throw ConversionError.invalidInput("无法读取图片: \(url.lastPathComponent)")
            }
            pdf.insert(page, at: index)
        }

        let out = try context.makeOutputURL(suffix: "_\(context.job.type.rawValue)", extension: "pdf")
        guard pdf.write(to: out) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }

    /// 旋转 PDF 的所有页面。
    ///
    /// 旋转角度从 `parameters.rotationDegrees` 获取，然后对每页的 `rotation` 属性
    /// 进行累加并取模 360。注意：这是**增量旋转**——每次旋转在当前已有角度的基础上叠加。
    private func rotatePDF(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF 文件")
        }
        guard let doc = PDFDocument(url: input) else {
            throw ConversionError.invalidInput("无法打开 PDF")
        }

        let degrees = context.job.parameters.rotationDegrees
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let rotation = (page.rotation + degrees) % 360
            page.rotation = rotation
            page.setBounds(bounds, for: .mediaBox)
        }

        let out = try context.makeOutputURL(suffix: "_\(context.job.type.rawValue)", extension: "pdf")
        guard doc.write(to: out) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }

    /// 将多个 PDF 合并为一个。
    ///
    /// 实现方式：创建一个空的 `PDFDocument`，遍历每个输入 PDF，将其所有页面
    /// 复制后依次追加到合并文档中。每一页都使用 `copy()` 创建副本，
    /// 避免修改原始文档对象的引用。
    ///
    /// - Note: 合并需要至少 2 个输入 PDF 文件
    private func mergePDF(context: ConversionContext) async throws -> ConversionResult {
        let inputs = context.job.inputURLs
        guard inputs.count >= 2 else {
            throw ConversionError.invalidInput("合并至少需要 2 个 PDF")
        }

        let merged = PDFDocument()
        var pageIndex = 0
        for url in inputs {
            guard let doc = PDFDocument(url: url) else {
                throw ConversionError.invalidInput("无法打开: \(url.lastPathComponent)")
            }
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i)?.copy() as? PDFPage {
                    merged.insert(page, at: pageIndex)
                    pageIndex += 1
                }
            }
        }

        let out = try context.makeOutputURL(suffix: "_\(context.job.type.rawValue)", extension: "pdf")
        guard merged.write(to: out) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }

    /// 在 PDF 每页添加半透明文字水印。
    ///
    /// 使用 `PDFAnnotation` 的 `.freeText` 类型在每页中央区域添加水印。
    /// 水印文字使用灰色半透明（`alphaComponent: 0.35`），确保不影响正文阅读。
    /// 水印位置设置在页面宽度 25%~75%、高度 45%~45%+40pt 的矩形区域内。
    ///
    /// - Note: 水印文字从 `parameters.watermarkText` 获取，为空时抛出错误
    private func watermarkPDF(context: ConversionContext) async throws -> ConversionResult {
        guard let input = context.job.inputURLs.first else {
            throw ConversionError.invalidInput("请选择 PDF")
        }
        guard let text = context.job.parameters.watermarkText, !text.isEmpty else {
            throw ConversionError.invalidInput("请输入水印文字")
        }
        guard let doc = PDFDocument(url: input) else {
            throw ConversionError.invalidInput("无法打开 PDF")
        }

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            // 水印占据页面中央约 50% 宽度、40pt 高度的区域
            let annotation = PDFAnnotation(bounds: CGRect(
                x: bounds.width * 0.25,
                y: bounds.height * 0.45,
                width: bounds.width * 0.5,
                height: 40
            ), forType: .freeText, withProperties: nil)
            annotation.contents = text
            annotation.font = NSFont.systemFont(ofSize: 24)
            annotation.fontColor = NSColor.gray.withAlphaComponent(0.35)
            annotation.color = .clear
            page.addAnnotation(annotation)
        }

        let out = try context.makeOutputURL(suffix: "_\(context.job.type.rawValue)", extension: "pdf")
        guard doc.write(to: out) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }
}