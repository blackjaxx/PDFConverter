import Foundation

public struct PageRange: Codable, Sendable, Equatable {
    public var start: Int
    public var end: Int?

    public init(start: Int = 1, end: Int? = nil) {
        self.start = start
        self.end = end
    }

    public var displayString: String {
        if let end {
            return "\(start)-\(end)"
        }
        return "\(start)"
    }
}

public struct ConversionParameters: Codable, Sendable {
    public var dpi: Int
    public var jpegQuality: Double
    public var pageRange: PageRange?
    public var rotationDegrees: Int
    public var password: String?
    public var ocrLanguages: [String]
    public var compressionLevel: String
    public var watermarkText: String?

    public init(
        dpi: Int = 150,
        jpegQuality: Double = 0.85,
        pageRange: PageRange? = nil,
        rotationDegrees: Int = 90,
        password: String? = nil,
        ocrLanguages: [String] = ["chi_sim", "eng"],
        compressionLevel: String = "ebook",
        watermarkText: String? = nil
    ) {
        self.dpi = dpi
        self.jpegQuality = jpegQuality
        self.pageRange = pageRange
        self.rotationDegrees = rotationDegrees
        self.password = password
        self.ocrLanguages = ocrLanguages
        self.compressionLevel = compressionLevel
        self.watermarkText = watermarkText
    }
}
