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

    /// 构造输出文件路径，优先使用 job.outputDirectory，回退到输入文件所在目录。
    /// 如果该路径已存在文件则先删除。
    public func makeOutputURL(suffix: String, extension ext: String) throws -> URL {
        guard let input = job.inputURLs.first else {
            throw ConversionError.invalidInput("没有输入文件")
        }
        let base = job.outputDirectory ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let url = base.appendingPathComponent(stem + suffix).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return url
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
    case aiNotConfigured(String)
    case aiRequestFailed(String)

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
        case .aiNotConfigured(let message):
            return message
        case .aiRequestFailed(let message):
            return "AI 请求失败: \(message)"
        }
    }
}

/// Pluggable conversion backend. Implement one engine per external dependency cluster.
public protocol ConversionEngine: Sendable {
    var kind: EngineKind { get }
    func supportedTypes() -> Set<ConversionType>
    func convert(context: ConversionContext) async throws -> ConversionResult
}
