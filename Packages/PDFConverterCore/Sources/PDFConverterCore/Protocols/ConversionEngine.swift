import Foundation

/// ``ConversionEngine`` 执行转换时的上下文，包含了引擎完成一次转换所需的全部环境信息。
///
/// 该结构体在 ``JobOrchestrator`` 的 `execute` 方法中被创建，然后传递给具体引擎的 `convert` 方法。
///
/// 为什么需要这个上下文？
/// - 引擎需要知道"正在处理什么任务"（`job`）
/// - 引擎需要一个隔离的临时工作目录来存放中间文件（`workDirectory`）
/// - 引擎需要知道 CLI 工具的根目录，以便通过 ``ToolLocator`` 查找可执行文件（`toolsRoot`）
public struct ConversionContext: Sendable {
    /// 当前正在处理的转换任务，包含输入文件、输出目录、转换参数等全部信息
    public let job: ConversionJob
    /// 引擎专属的临时工作目录，任务完成后由 ``JobOrchestrator`` 自动清理
    public let workDirectory: URL
    /// App 内捆绑工具集的根目录路径（例如 `Resources/tools`），可能为 nil
    public let toolsRoot: URL?

    public init(job: ConversionJob, workDirectory: URL, toolsRoot: URL?) {
        self.job = job
        self.workDirectory = workDirectory
        self.toolsRoot = toolsRoot
    }

    /// 构造输出文件路径，优先使用 job.outputDirectory，回退到输入文件所在目录。
    /// 如果该路径已存在文件则先删除。
    ///
    /// 这个方法保证了所有引擎使用统一的输出路径构造逻辑，避免每个引擎各自实现而导致路径不一致。
    ///
    /// - Parameters:
    ///   - suffix: 添加到文件名末尾的后缀（例如 `"_compressed"`、`"_ocr"`）
    ///   - ext: 输出文件的扩展名（不带点，例如 `"pdf"`、`"png"`）
    /// - Returns: 构造好的输出文件 URL
    /// - Throws: 如果输入文件列表为空，抛出 `invalidInput` 错误
    public func makeOutputURL(suffix: String, extension ext: String) throws -> URL {
        guard let input = job.inputURLs.first else {
            throw ConversionError.invalidInput("没有输入文件")
        }
        // 输出目录的优先级：用户指定的 outputDirectory > 输入文件所在目录
        let base = job.outputDirectory ?? input.deletingLastPathComponent()
        // 取输入文件的主文件名（不含扩展名），拼接后缀和新的扩展名
        let stem = input.deletingPathExtension().lastPathComponent
        let url = base.appendingPathComponent(stem + suffix).appendingPathExtension(ext)
        // 如果目标文件已存在则先删除，避免写入冲突
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }
}

/// 一次转换操作的结果，包含生成的文件和过程日志。
public struct ConversionResult: Sendable {
    /// 转换产生的输出文件列表。
    /// 大多数转换只生成一个文件（如 PDF 转 PNG 可能生成多张图片），但某些转换
    /// （如 PDF 拆分）会产生多个文件，因此使用数组。
    public let outputURLs: [URL]
    /// 转换过程中的日志信息，用于调试和展示给用户
    public let logs: String

    public init(outputURLs: [URL], logs: String = "") {
        self.outputURLs = outputURLs
        self.logs = logs
    }
}

/// 转换引擎可能抛出的所有错误类型。
///
/// 每个 case 代表转换流水线中一个特定的失败环节，
/// 包括输入验证、工具查找、进程执行、输出验证以及 AI 功能相关的错误。
public enum ConversionError: Error, LocalizedError, Sendable {
    /// 当前引擎不支持该转换类型。
    /// 例如把 `.mergePDF` 交给 ``PopplerEngine`` 处理时就会触发此错误。
    case unsupportedType(ConversionType)
    /// 未找到所需的 CLI 工具。
    /// 通常是因为 `Resources/tools` 目录下没有对应工具，且系统 PATH 中也找不到。
    /// 解决方法是运行 `Scripts/bundle-tools.sh` 重新打包工具。
    case missingTool(String)
    /// 输入文件无效，例如文件损坏、格式不匹配或用户未选择文件。
    case invalidInput(String)
    /// 外部命令执行失败（退出码非 0）。
    /// `command` 是执行的完整命令，`exitCode` 是进程退出码，`stderr` 是标准错误输出。
    case processFailed(command: String, exitCode: Int32, stderr: String)
    /// 转换完成后预期输出文件不存在。
    /// 可能是外部工具静默失败，或输出文件被错误地写到了其他位置。
    case outputMissing(String)
    /// AI 功能未配置（如未设置 DeepSeek API Key）。
    case aiNotConfigured(String)
    /// AI 请求失败（网络错误、API 返回错误等）。
    case aiRequestFailed(String)

    /// 为每个错误 case 提供用户友好的中文错误描述。
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

/// 可插拔转换引擎的设计基石。
///
/// 这是整个 PDFConverterCore 架构中最核心的协议。每一个转换后端（如 PDFKit、Poppler、qpdf 等）
/// 都需要实现这个协议。这种设计带来了两个关键好处：
///
/// 1. **可插拔性**：新增引擎只需实现 `kind`、`supportedTypes()`、`convert()` 三个方法，
///    然后在 ``EngineRegistry`` 中注册即可，无需修改任何核心代码。
///
/// 2. **解耦**：``JobOrchestrator`` 只依赖这个协议，不关心具体是哪个引擎在工作，
///    这使得单元测试中可以轻松替换为 Mock 引擎。
///
/// 协议要求 `Sendable` 一致性，因为引擎实例会在 Swift Actor 之间传递。
///
/// ## 实现一个新引擎的步骤
/// 1. 创建一个 struct 实现 ``ConversionEngine``
/// 2. 实现 `kind` 返回唯一的 ``EngineKind`` 标识
/// 3. 实现 `supportedTypes()` 返回该引擎能处理的所有 ``ConversionType``
/// 4. 实现 `convert(context:)` 完成实际的转换逻辑
/// 5. 在 ``EngineRegistry`` 的初始化列表中加入该引擎
public protocol ConversionEngine: Sendable {
    /// 引擎的种类标识，与 ``EngineKind`` 一一对应。
    /// 用于在 ``EngineRegistry`` 中按种类查找引擎。
    var kind: EngineKind { get }
    /// 返回该引擎能处理的所有转换类型。
    /// ``EngineRegistry`` 会根据这个列表构建 `ConversionType → Engine` 的映射表。
    func supportedTypes() -> Set<ConversionType>
    /// 执行实际的转换操作。
    /// - Parameter context: 包含任务信息、工作目录和工具路径的上下文
    /// - Returns: 转换结果，包含输出文件列表和日志
    /// - Throws: ``ConversionError`` 的各种 case
    func convert(context: ConversionContext) async throws -> ConversionResult
}