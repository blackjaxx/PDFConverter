import Foundation
import PDFKit
import AppKit
public struct PDFKitEngine: ConversionEngine {
    public let kind: EngineKind = .pdfKit

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

        let out = try defaultOutputURL(context: context, extension: "pdf")
        guard pdf.write(to: out) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }

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

        let out = try defaultOutputURL(context: context, extension: "pdf")
        guard doc.write(to: out) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }

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

        let out = try defaultOutputURL(context: context, extension: "pdf")
        guard merged.write(to: out) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }

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

        let out = try defaultOutputURL(context: context, extension: "pdf")
        guard doc.write(to: out) else {
            throw ConversionError.outputMissing(out.path)
        }
        return ConversionResult(outputURLs: [out])
    }

    private func defaultOutputURL(context: ConversionContext, extension ext: String) throws -> URL {
        let base = context.job.outputDirectory
            ?? context.job.inputURLs.first?.deletingLastPathComponent()
            ?? context.workDirectory
        let stem = context.job.inputURLs.first?.deletingPathExtension().lastPathComponent ?? "output"
        let name = "\(stem)_\(context.job.type.rawValue).\(ext)"
        let url = base.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }
}
