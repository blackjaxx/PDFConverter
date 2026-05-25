import Foundation

/// Central registry: maps ConversionType → engine. Add engines here when extending.
public final class EngineRegistry: @unchecked Sendable {
    public static let shared = EngineRegistry()

    private let engines: [any ConversionEngine]
    private let typeIndex: [ConversionType: any ConversionEngine]

    public init(engines: [any ConversionEngine]? = nil) {
        let list = engines ?? [
            PDFKitEngine(),
            PopplerEngine(),
            QpdfEngine(),
            GhostscriptEngine(),
            LibreOfficeEngine(),
            TesseractEngine(),
            WebKitEngine(),
            LLMEngine()
        ]
        self.engines = list

        var index: [ConversionType: any ConversionEngine] = [:]
        for engine in list {
            for type in engine.supportedTypes() {
                index[type] = engine
            }
        }
        self.typeIndex = index
    }

    public func engine(for type: ConversionType) -> (any ConversionEngine)? {
        typeIndex[type]
    }

    public func allEngines() -> [any ConversionEngine] {
        engines
    }

    public func types(for kind: EngineKind) -> [ConversionType] {
        engines
            .filter { $0.kind == kind }
            .flatMap { Array($0.supportedTypes()) }
            .sorted { $0.displayName < $1.displayName }
    }
}
