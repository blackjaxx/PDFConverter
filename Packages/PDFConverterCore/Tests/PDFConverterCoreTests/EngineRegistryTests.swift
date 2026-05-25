import XCTest
@testable import PDFConverterCore

final class EngineRegistryTests: XCTestCase {
    func testEveryTypeHasEngine() {
        let registry = EngineRegistry()
        for type in ConversionType.allCases {
            XCTAssertNotNil(registry.engine(for: type), "Missing engine for \(type.rawValue)")
        }
    }

    func testOCRUsesTesseract() {
        let registry = EngineRegistry()
        let engine = registry.engine(for: .ocrSearchablePDF)
        XCTAssertEqual(engine?.kind, .tesseract)
    }

    func testAIUsesDeepSeekEngine() {
        let registry = EngineRegistry()
        XCTAssertEqual(registry.engine(for: .pdfAISummary)?.kind, .deepSeek)
    }
}
