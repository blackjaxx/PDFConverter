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
///
/// v0.4.3 新增 `stderrDetails` 字段，用于存储完整错误详情（stdout/stderr），
/// 与 `errorMessage`（短描述）区分。UI 可以展开查看完整详情。
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
    /// v0.4.3：完整错误详情（包含 stdout/stderr 等技术信息）
    public var stderrDetails: String?
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
        stderrDetails: String? = nil,
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
        self.stderrDetails = stderrDetails
        self.createdAt = createdAt
    }
}