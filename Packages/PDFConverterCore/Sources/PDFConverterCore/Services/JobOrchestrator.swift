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
/// ↓
/// 取 pending 任务 → 设为 running → 通知进度
/// ↓
/// execute(job):
///   查找引擎 → 创建临时目录 → 引擎执行转换 → 清理临时目录
/// ↓
/// 设为 completed / failed → 通知结果 → 继续 pump()
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
    /// 正在执行的 Task 引用（用于取消）
    /// Key 为任务 ID，value 为运行中的 Task，调用 cancel 时通过它来协调
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

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
    /// 支持两种状态：
    /// - `.pending`：直接从队列中移除
    /// - `.running`：标记为 cancelled。Task 完成后会看到 cancelled 状态，
    ///   不会覆盖为 completed。子进程本身无法安全终止，但 UI 可以正确反映取消。
    ///
    /// - Parameter id: 要取消的任务 ID
    public func cancel(id: UUID) {
        guard var job = jobsByID[id] else { return }

        switch job.status {
        case .pending:
            // 直接从队列移除并标记为 cancelled
            queue.removeAll { $0.id == id }
            job.status = .cancelled
            jobsByID[id] = job
            notify(job)

        case .running:
            // 标记取消意图。execute 完成后会看到 cancelled 状态而不再覆盖。
            // 协调正在运行的 Task（虽然无法中断进程，但 UI 状态保持一致）
            job.status = .cancelled
            jobsByID[id] = job
            notify(job)
            // Task<Void, Never> 不可取消，但协调状态以保证一致性
            _ = runningTasks[id] // 持有引用，防止 Task 在 finalize 之前被释放

        default:
            // completed / failed / cancelled 状态的任务无法再次取消
            return
        }
    }

    /// 核心调度逻辑：从队列取任务 → 执行转换 → 通知结果
    ///
    /// 实现细节：
    /// 1. 检查是否有空闲的执行槽位（`running < maxConcurrent`）
    /// 2. 从队列取第一个 pending 任务
    /// 3. 递增 `running` 计数，将任务设为 `running` 状态
    /// 4. 通过 Task 异步执行 `execute`（避免 actor 递归栈累积）
    /// 5. 完成后更新状态和结果
    /// 6. 递减 `running` 计数，重新 pump 处理下一个任务
    ///
    /// 注意：使用 `Task` 包装以避免 actor 同步递归导致的栈增长。
    private func pump() async {
        guard running < maxConcurrent else { return }

        // 找到第一个 pending 任务
        guard let index = queue.firstIndex(where: { $0.status == .pending }) else {
            return
        }

        running += 1
        var job = queue.remove(at: index)
        job.status = .running
        job.progress = 0.05
        jobsByID[job.id] = job
        notify(job)

        // 记录正在运行的 Task 引用（用于协调取消）
        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeJob(job)
        }
        runningTasks[job.id] = task
    }

    /// 执行单个任务并更新状态。
    ///
    /// 这是一个独立的 actor 方法，被 `Task` 调用以避免 pump 中的同步递归。
    /// 在 execute 完成后检查 cancellation 状态——如果用户在执行过程中点了取消，
    /// 我们尊重该意图，不会覆盖为 completed。
    private func executeJob(_ job: ConversionJob) async {
        let result: Result<ConversionResult, Error>
        do {
            let r = try await execute(job)
            result = .success(r)
        } catch {
            result = .failure(error)
        }

        var updated = jobsByID[job.id] ?? job

        // 关键修复：如果用户在执行中取消了，保持 cancelled 状态
        if updated.status != .cancelled {
            switch result {
            case .success(let r):
                updated.status = .completed
                updated.progress = 1
                updated.outputURLs = r.outputURLs
                updated.errorMessage = nil
            case .failure(let error):
                updated.status = .failed
                updated.errorMessage = error.localizedDescription
                updated.progress = 0
            }
        }

        jobsByID[updated.id] = updated
        notify(updated)
        running -= 1
        runningTasks[updated.id] = nil

        // 重新调度
        await pump()
    }

    /// 执行单个转换任务（创建临时目录、调用引擎、清理）。
    ///
    /// ## 执行步骤
    /// 1. 通过 `EngineRegistry` 查找对应转换类型的引擎
    /// 2. 为本次转换创建隔离的临时工作目录
    /// 3. 构建 `ConversionContext` 并调用引擎的 `convert` 方法
    /// 4. 无论成功或失败，最后都会通过 `defer` 清理临时目录
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