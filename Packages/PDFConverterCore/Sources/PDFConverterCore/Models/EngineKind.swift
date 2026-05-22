import Foundation

/// Identifies which backend executes a conversion. Register new engines without touching the UI.
public enum EngineKind: String, CaseIterable, Codable, Sendable {
    case pdfKit
    case poppler
    case qpdf
    case ghostscript
    case libreOffice
    case tesseract
    case webKit
}

public struct BundledTool: Sendable {
    public let name: String
    public let relativePath: String
    public let engine: EngineKind

    public init(name: String, relativePath: String, engine: EngineKind) {
        self.name = name
        self.relativePath = relativePath
        self.engine = engine
    }
}

public enum BundledToolsCatalog {
    public static let all: [BundledTool] = [
        BundledTool(name: "pdftoppm", relativePath: "poppler/pdftoppm", engine: .poppler),
        BundledTool(name: "pdftotext", relativePath: "poppler/pdftotext", engine: .poppler),
        BundledTool(name: "qpdf", relativePath: "qpdf/qpdf", engine: .qpdf),
        BundledTool(name: "gs", relativePath: "ghostscript/gs", engine: .ghostscript),
        BundledTool(name: "soffice", relativePath: "libreoffice/soffice", engine: .libreOffice),
        BundledTool(name: "tesseract", relativePath: "tesseract/tesseract", engine: .tesseract)
    ]
}
