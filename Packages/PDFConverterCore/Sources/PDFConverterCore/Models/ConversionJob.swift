import Foundation

/// 转换任务的生命周期状态。
///
/// 任务状态流转路径：
/// ```
/// pending → running → completed
///                   → failed
/// pending → cancelled  （仅在未开始执行时可以取消）
/// ```
/// 一旦任务进入 `running` 状态，它只能走向 `completed` 或 `failed`，
/// 不会再回到 `pending`。取消操作只对 `pending` 状态的任务有效。
public enum JobStatus: String, Codable, Sendable {
    /// 任务已入队，等待调度器分配执行
    case pending
    /// 任务正在被某个引擎执行
    case running
    /// 转换成功完成
    case completed
    /// 转换过程中发生错误
    case failed
    /// 任务被用户手动取消（仅在 pending 状态有效）
    case cancelled
}

/// 一个转换任务实例，包含执行一次转换所需的全部信息。
///
/// 这个结构体是整个系统的"工作单元"——用户通过 UI 创建任务后，
/// 它被送入 ``JobOrchestrator`` 的队列，由调度器分配给对应的引擎执行。
///
/// 设计要点：
/// - 实现 `Identifiable`（通过 `UUID`），方便 SwiftUI 的 `ForEach` 和列表渲染
/// - 实现 `Codable`，支持任务序列化和持久化（例如保存历史记录到磁盘）
/// - 采用值类型（`struct`）而非引用类型，配合 ``JobOrchestrator``（`actor`）保证并发安全
public struct ConversionJob: Identifiable, Codable, Sendable {
    /// 任务的唯一标识，使用 UUID 保证全局唯一
    public let id: UUID
    /// 要执行的转换类型，决定了由哪个引擎处理
    public var type: ConversionType
    /// 输入文件列表，大多数转换只需要一个文件，合并等操作需要多个
    public var inputURLs: [URL]
    /// 用户指定的输出目录（可选），为空时输出到输入文件所在目录
    public var outputDirectory: URL?
    /// 转换参数，包括 DPI、质量、页码范围、密码等
    public var parameters: ConversionParameters
    /// 当前任务状态
    public var status: JobStatus
    /// 执行进度（0.0 ~ 1.0），用于 UI 进度条展示
    public var progress: Double
    /// 任务完成后生成的输出文件 URL 列表
    public var outputURLs: [URL]
    /// 任务失败时的错误描述
    public var errorMessage: String?
    /// 任务创建时间戳，用于按时间排序展示历史记录
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