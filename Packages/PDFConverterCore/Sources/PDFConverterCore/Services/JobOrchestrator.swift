import Foundation

/// 任务进度回调类型：`(任务ID, 当前进度 0~1, 当前状态) -> Void`
///
/// 必须在 MainActor 上执行（因为 UI 更新必须在主线程）。
public typealias JobProgressHandler = @MainActor @Sendable (UUID, Double, JobStatus) -> Void

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
///
/// ## 进度通知
/// 通过 `progressHandler` 回调通知 UI 层任务状态变更。
/// 关键修复（v0.4.2）：
/// - 回调标注为 `@MainActor @Sendable`，保证在主线程上调用
/// - 提供 `updateProgress(_:progress:)` 让引擎在转换过程中更新进度
/// - 提供 `observeJobs()` AsyncStream，UI 可以订阅状态变化而不需要定时器轮询
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
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    /// 状态变更观察者列表（AsyncStream continuations）
    /// UI 可以订阅这些流来接收任务状态变化，避免定时器轮询
    private var observers: [UUID: AsyncStream<[ConversionJob]>.Continuation] = [:]

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
    ///   - progressHandler: UI 层的进度回调（在主线程上调用）
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
        broadcastUpdate()
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
            broadcastUpdate()

        case .running:
            // 标记取消意图。execute 完成后会看到 cancelled 状态而不再覆盖。
            job.status = .cancelled
            jobsByID[id] = job
            notify(job)
            broadcastUpdate()
            _ = runningTasks[id]

        default:
            // completed / failed / cancelled 状态的任务无法再次取消
            return
        }
    }

    /// 更新某个任务的进度（供引擎在转换过程中调用）。
    ///
    /// 例如 PDF 转 PNG 这种多页转换，引擎每完成一页可以调用此方法更新进度。
    ///
    /// - Parameters:
    ///   - id: 任务 ID
    ///   - progress: 新的进度值（0.0 ~ 1.0）
    public func updateProgress(id: UUID, progress: Double) {
        guard var job = jobsByID[id], job.status == .running else { return }
        let clamped = max(0.0, min(1.0, progress))
        // 进度只能递增（不能倒退）
        if clamped > job.progress {
            job.progress = clamped
            jobsByID[id] = job
            notify(job)
            broadcastUpdate()
        }
    }

    /// 核心调度逻辑：从队列取任务 → 执行转换 → 通知结果
    private func pump() async {
        guard running < maxConcurrent else { return }

        guard let index = queue.firstIndex(where: { $0.status == .pending }) else {
            return
        }

        running += 1
        var job = queue.remove(at: index)
        job.status = .running
        job.progress = 0.05
        jobsByID[job.id] = job
        notify(job)
        broadcastUpdate()

        // 修复：将 job 作为 let 捕获，避免 Swift 6 并发模式下编译错误
        let jobCopy = job
        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeJob(jobCopy)
        }
        runningTasks[job.id] = task
    }

    /// 执行单个任务并更新状态。
    ///
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
        broadcastUpdate()
        running -= 1
        runningTasks[updated.id] = nil

        await pump()
    }

    /// 执行单个转换任务（创建临时目录、调用引擎、清理）。
    private func execute(_ job: ConversionJob) async throws -> ConversionResult {
        guard let engine = registry.engine(for: job.type) else {
            throw ConversionError.unsupportedType(job.type)
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFConverter", isDirectory: true)
            .appendingPathComponent(job.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: workDir)
        }

        let context = ConversionContext(job: job, workDirectory: workDir, toolsRoot: toolsRoot)
        return try await engine.convert(context: context)
    }

    /// 通过进度回调通知 UI 层任务状态变更（在主线程上执行）。
    private func notify(_ job: ConversionJob) {
        guard let handler = progressHandler else { return }
        // 进度回调必须在主线程上调用（@MainActor）
        Task { @MainActor in
            handler(job.id, job.progress, job.status)
        }
    }

    // MARK: - 观察者模式（v0.4.2 新增）

    /// 订阅任务状态变化，返回 AsyncStream。
    ///
    /// UI 层可以用 `.task` modifier 订阅这个流，无需定时器轮询：
    /// ```swift
    /// .task {
    ///     for await jobs in orchestrator.observeJobs() {
    ///         self.jobs = jobs
    ///     }
    /// }
    /// ```
    ///
    /// - Returns: 每次状态变化时推送最新任务列表的 AsyncStream
    public func observeJobs() -> AsyncStream<[ConversionJob]> {
        AsyncStream { continuation in
            // 注册观察者
            let observerID = UUID()
            self.observers[observerID] = continuation

            // 立即推送当前状态
            continuation.yield(allJobs())

            // 当流被取消时移除观察者
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeObserver(id: observerID) }
            }
        }
    }

    /// 移除观察者（内部使用）
    private func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }

    /// 通知所有观察者状态变化
    private func broadcastUpdate() {
        let snapshot = allJobs()
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }
}