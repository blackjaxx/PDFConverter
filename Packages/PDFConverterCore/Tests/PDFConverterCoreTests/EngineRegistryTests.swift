import XCTest
@testable import PDFConverterCore

final class EngineRegistryTests: XCTestCase {
    func testLocalTypeHasEngine() {
        let registry = EngineRegistry()
        for type in ConversionType.allCases where !type.requiresNetwork {
            XCTAssertNotNil(registry.engine(for: type), "Missing engine for \(type.rawValue)")
        }
    }

    func testNetworkTypesReturnNilInCoreRegistry() {
        let registry = EngineRegistry()
        let networkTypes: [ConversionType] = [.htmlToPDF, .pdfAISummary, .pdfAITranslate, .pdfAIToMarkdown]
        for type in networkTypes {
            XCTAssertNil(registry.engine(for: type), "Network type \(type.rawValue) should not have engine in core registry")
        }
    }

    func testOCRUsesTesseract() {
        let registry = EngineRegistry()
        let engine = registry.engine(for: .ocrSearchablePDF)
        XCTAssertEqual(engine?.kind, .tesseract)
    }

    func testMergePDFUsesPDFKit() {
        let registry = EngineRegistry()
        let engine = registry.engine(for: .mergePDF)
        XCTAssertEqual(engine?.kind, .pdfKit)
    }
}