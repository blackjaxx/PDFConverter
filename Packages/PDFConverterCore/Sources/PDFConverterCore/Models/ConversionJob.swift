import Foundation

public enum JobStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

public struct ConversionJob: Identifiable, Codable, Sendable {
    public let id: UUID
    public var type: ConversionType
    public var inputURLs: [URL]
    public var outputDirectory: URL?
    public var parameters: ConversionParameters
    public var status: JobStatus
    public var progress: Double
    public var outputURLs: [URL]
    public var errorMessage: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        type: ConversionType,
        inputURLs: [URL],
        outputDirectory: URL? = nil,
        parameters: ConversionParameters = .init(),
        status: JobStatus = .pending,
        progress: Double = 0,
        outputURLs: [URL] = [],
        errorMessage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.inputURLs = inputURLs
        self.outputDirectory = outputDirectory
        self.parameters = parameters
        self.status = status
        self.progress = progress
        self.outputURLs = outputURLs
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}
