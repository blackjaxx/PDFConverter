import Foundation

/// 任务进度回调类型：`(任务ID, 当前进度 0~1, 当前状态) -> Void`
public typealias JobProgressHandler = @Sendable (UUID, Double, JobStatus) -> Void

/// 任务编排器，管理任务队列和并发执行。
///
/// 这是整个转换引擎的"大脑"——负责接收任务、排队、调度执行、通知结果。
///
/// 为什么使用 `actor`？
/// - 任务队列和运行时计数是共享的可变状态，需要线程安全保护
/// - `actor` 是 Swift 原生的并发安全机制，比手动加锁更简洁且不容易出错
/// - `Sendable` 约束确保所有在 actor 边界传递的数据都是线程安全的
///
/// ## 执行流程概览
/// ```
/// enqueue(job) → pump()
///                  ↓
///            取 pending 任务 → 设为 running → 通知进度
///                  ↓
///            execute(job):
///              查找引擎 → 创建临时目录 → 引擎执行转换 → 清理临时目录
///                  ↓
///            设为 completed / failed → 通知结果 → 继续 pump()
/// ```
///
/// ## 并发控制
/// `maxConcurrent` 参数限制了同时执行的任务数量（默认 2），
/// 防止同时启动过多外部进程导致系统资源耗尽。
public actor JobOrchestrator {
    /// 全局共享实例
    public static let shared = JobOrchestrator()

    /// 引擎注册表
    private var registry: EngineRegistry
    /// 最大并发任务数
    private let maxConcurrent: Int
    /// 待处理任务队列
    private var queue: [ConversionJob] = []
    /// 当前正在运行的任务数
    private var running = 0
    /// 所有任务的内存存储（ID → Job），用于查询和更新
    private var jobsByID: [UUID: ConversionJob] = [:]
    /// 进度回调，由 UI 层设置以接收实时更新
    private var progressHandler: JobProgressHandler?
    /// 捆绑工具集的根目录
    private var toolsRoot: URL?

    public init(registry: EngineRegistry = .shared, maxConcurrent: Int = 2) {
        self.registry = registry
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// 初始化编排器的运行环境。
    ///
    /// 这个方法通常在 App 启动时调用一次，设置工具路径、注册引擎和进度回调。
    ///
    /// - Parameters:
    ///   - toolsRoot: App Bundle 中工具集的根目录（通常是 `Resources/tools`）
    ///   - registry: 可选的引擎注册表，不传则使用当前已注册的引擎
    ///   - progressHandler: UI 层的进度回调
    public func configure(
        toolsRoot: URL?,
        registry: EngineRegistry? = nil,
        progressHandler: JobProgressHandler? = nil
    ) {
        self.toolsRoot = toolsRoot
        if let registry {
            self.registry = registry
        }
        self.progressHandler = progressHandler
        // 同步更新 ToolLocator 的工具根目录，确保引擎能正常查找到 CLI 工具
        ToolLocator.shared.configure(toolsRoot: toolsRoot)
    }

    /// 将任务加入队列，状态设为 `pending`。
    ///
    /// - Parameter job: 要添加的转换任务
    public func enqueue(_ job: ConversionJob) {
        var j = job
        j.status = .pending
        jobsByID[j.id] = j
        queue.append(j)
        // 异步触发调度，不阻塞调用方
        Task { await pump() }
    }

    /// 获取所有任务，按创建时间倒序排列（最新的在前）。
    public func allJobs() -> [ConversionJob] {
        jobsByID.values.sorted { $0.createdAt > $1.createdAt }
    }

    /// 取消指定 ID 的任务。
    ///
    /// - Note: 只能取消 `pending` 状态的任务。`running` 状态的任务
    ///   已经交由引擎执行，无法中断（因为外部进程的终止需要额外处理）。
    ///
    /// - Parameter id: 要取消的任务 ID
    public func cancel(id: UUID) {
        guard var job = jobsByID[id], job.status == .pending || job.status == .running else { return }
        job.status = .cancelled
        jobsByID[id] = job
        queue.removeAll { $0.id == id }
        notify(job)
    }

    /// 核心调度逻辑：从队列取任务 → 执行转换 → 通知结果
    ///
    /// 使用递归调用实现自驱动调度：
    /// 1. 检查是否有空闲的执行槽位（`running < maxConcurrent`）
    /// 2. 从队列取第一个 pending 任务
    /// 3. 递增 `running` 计数，将任务设为 `running` 状态
    /// 4. 异步执行 `execute`，完成后更新状态和结果
    /// 5. 递减 `running` 计数，递归调用自己处理下一个任务
    ///
    /// 这种递归模式确保了：只要队列中有 pending 任务且有空闲槽位，
    /// 调度就会持续进行，直到队列为空或达到并发上限。
    private func pump() async {
        guard running < maxConcurrent, let index = queue.firstIndex(where: { $0.status == .pending }) else {
            return
        }

        running += 1
        var job = queue.remove(at: index)
        job.status = .running
        job.progress = 0.05
        jobsByID[job.id] = job
        notify(job)

        do {
            let result = try await execute(job)
            job.status = .completed
            job.progress = 1
            job.outputURLs = result.outputURLs
            job.errorMessage = nil
        } catch {
            job.status = .failed
            job.errorMessage = error.localizedDescription
            job.progress = 0
        }

        jobsByID[job.id] = job
        notify(job)
        running -= 1
        // 递归调用，处理队列中的下一个任务
        await pump()
    }

    /// 执行单个转换任务。
    ///
    /// ## 执行步骤
    /// 1. 通过 ``EngineRegistry`` 查找对应转换类型的引擎
    /// 2. 为本次转换创建隔离的临时工作目录（路径为 `/tmp/PDFConverter/<jobID>/`）
    /// 3. 构建 ``ConversionContext`` 并调用引擎的 `convert` 方法
    /// 4. 无论成功或失败，最后都会通过 `defer` 清理临时目录
    ///
    /// 为什么每个任务使用独立的临时目录？
    /// - 隔离性：避免并发任务的文件名冲突
    /// - 安全性：任务完成后自动清理，不留垃圾文件
    /// - 可调试性：出问题时可以直接查看临时目录的中间文件
    private func execute(_ job: ConversionJob) async throws -> ConversionResult {
        guard let engine = registry.engine(for: job.type) else {
            throw ConversionError.unsupportedType(job.type)
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFConverter", isDirectory: true)
            .appendingPathComponent(job.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        defer {
            // 无论转换成功与否，都清理临时目录
            try? FileManager.default.removeItem(at: workDir)
        }

        let context = ConversionContext(job: job, workDirectory: workDir, toolsRoot: toolsRoot)
        return try await engine.convert(context: context)
    }

    /// 通过进度回调通知 UI 层任务状态变更。
    private func notify(_ job: ConversionJob) {
        progressHandler?(job.id, job.progress, job.status)
    }
}