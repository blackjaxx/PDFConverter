import Foundation

public struct ConversionContext: Sendable {
    public let job: ConversionJob
    public let workDirectory: URL
    public let toolsRoot: URL?

    public init(job: ConversionJob, workDirectory: URL, toolsRoot: URL?) {
        self.job = job
        self.workDirectory = workDirectory
        self.toolsRoot = toolsRoot
    }
}

public struct ConversionResult: Sendable {
    public let outputURLs: [URL]
    public let logs: String

    public init(outputURLs: [URL], logs: String = "") {
        self.outputURLs = outputURLs
        self.logs = logs
    }
}

public enum ConversionError: Error, LocalizedError, Sendable {
    case unsupportedType(ConversionType)
    case missingTool(String)
    case invalidInput(String)
    case processFailed(command: String, exitCode: Int32, stderr: String)
    case outputMissing(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let type):
            return "不支持的转换类型: \(type.displayName)"
        case .missingTool(let name):
            return "未找到本地工具: \(name)。请运行 Scripts/bundle-tools.sh 或将工具放入 Resources/tools。"
        case .invalidInput(let message):
            return "输入无效: \(message)"
        case .processFailed(let command, let exitCode, let stderr):
            return "命令失败 (\(exitCode)): \(command)\n\(stderr)"
        case .outputMissing(let path):
            return "未生成输出文件: \(path)"
        }
    }
}

/// Pluggable conversion backend. Implement one engine per external dependency cluster.
public protocol ConversionEngine: Sendable {
    var kind: EngineKind { get }
    func supportedTypes() -> Set<ConversionType>
    func convert(context: ConversionContext) async throws -> ConversionResult
}
