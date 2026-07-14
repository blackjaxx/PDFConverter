import Foundation

/// 任务进度回调类型：`(任务ID, 当前进度 0~1, 当前状态) -> Void`
public typealias JobProgressHandler = @MainActor @Sendable (UUID, Double, JobStatus) -> Void

public actor JobOrchestrator {
    public static let shared = JobOrchestrator()

    private var registry: EngineRegistry
    private let maxConcurrent: Int
    private var queue: [ConversionJob] = []
    private var running = 0
    private var jobsByID: [UUID: ConversionJob] = [:]
    private var progressHandler: JobProgressHandler?
    private var toolsRoot: URL?
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var observers: [UUID: AsyncStream<[ConversionJob]>.Continuation] = [:]

    public init(registry: EngineRegistry = .shared, maxConcurrent: Int = 2) {
        self.registry = registry
        self.maxConcurrent = max(1, maxConcurrent)
    }

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
        ToolLocator.shared.configure(toolsRoot: toolsRoot)
    }

    public func enqueue(_ job: ConversionJob) {
        var j = job
        j.status = .pending
        jobsByID[j.id] = j
        queue.append(j)
        broadcastUpdate()
        Task { await pump() }
    }

    public func allJobs() -> [ConversionJob] {
        jobsByID.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func cancel(id: UUID) {
        guard var job = jobsByID[id] else { return }

        switch job.status {
        case .pending:
            queue.removeAll { $0.id == id }
            job.status = .cancelled
            jobsByID[id] = job
            notify(job)
            broadcastUpdate()
        case .running:
            job.status = .cancelled
            jobsByID[id] = job
            notify(job)
            broadcastUpdate()
            _ = runningTasks[id]
        default:
            return
        }
    }

    public func updateProgress(id: UUID, progress: Double) {
        guard var job = jobsByID[id], job.status == .running else { return }
        let clamped = max(0.0, min(1.0, progress))
        if clamped > job.progress {
            job.progress = clamped
            jobsByID[id] = job
            notify(job)
            broadcastUpdate()
        }
    }

    private func pump() async {
        guard running < maxConcurrent else { return }
        guard let index = queue.firstIndex(where: { $0.status == .pending }) else { return }

        running += 1
        var job = queue.remove(at: index)
        job.status = .running
        job.progress = 0.05
        jobsByID[job.id] = job
        notify(job)
        broadcastUpdate()

        let jobCopy = job
        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeJob(jobCopy)
        }
        runningTasks[job.id] = task
    }

    /// 执行单个任务并更新状态。
    ///
    /// v0.4.3 增强：
    /// - 失败时尝试从 ConversionError 提取 stderr 等详细信息
    /// - 失败信息会同时填充到 job.errorMessage（短）和 stderr 长文本（供详情查看）
    private func executeJob(_ job: ConversionJob) async {
        let result: Result<ConversionResult, Error>
        do {
            let r = try await execute(job)
            result = .success(r)
        } catch {
            result = .failure(error)
        }

        var updated = jobsByID[job.id] ?? job

        if updated.status != .cancelled {
            switch result {
            case .success(let r):
                updated.status = .completed
                updated.progress = 1
                updated.outputURLs = r.outputURLs
                updated.errorMessage = nil
            case .failure(let error):
                updated.status = .failed
                // v0.4.3：智能提取错误信息
                // ConversionError.processFailed 有 command + exitCode + stderr
                // 其他错误用 localizedDescription
                let (short, details) = extractErrorInfo(error)
                updated.errorMessage = short
                updated.stderrDetails = details
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

    /// 从 Error 提取错误信息。
    /// - Returns: (简短描述, 详细信息（可选）)
    private func extractErrorInfo(_ error: Error) -> (String, String?) {
        if let convError = error as? ConversionError {
            switch convError {
            case .processFailed(let command, let exitCode, let stderr):
                let short = "命令失败 (退出码 \(exitCode))"
                let details = """
                命令: \(command)
                退出码: \(exitCode)
                错误输出:
                \(stderr.isEmpty ? "(空)" : stderr)
                """
                return (short, details)
            case .missingTool(let name):
                if name == "soffice" {
                    let details = """
                    Office 文档转换需要 LibreOffice 或 Microsoft Office / Apple iWork。

                    三种解决方案（按推荐顺序）：
                    1. Microsoft Office 365（已安装则自动使用）
                    2. Apple iWork（Pages/Numbers/Keynote，已安装则自动使用）
                    3. 安装 LibreOffice: brew install --cask libreoffice
                       或下载: https://www.libreoffice.org/download/
                    """
                    return (convError.errorDescription ?? "缺少工具: \(name)", details)
                }
                return (convError.errorDescription ?? "缺少工具: \(name)", nil)
            case .unsupportedType, .invalidInput, .outputMissing, .aiNotConfigured, .aiRequestFailed:
                return (convError.errorDescription ?? error.localizedDescription, nil)
            }
        }
        return (error.localizedDescription, nil)
    }

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

    private func notify(_ job: ConversionJob) {
        guard let handler = progressHandler else { return }
        Task { @MainActor in
            handler(job.id, job.progress, job.status)
        }
    }

    public func observeJobs() -> AsyncStream<[ConversionJob]> {
        AsyncStream { continuation in
            let observerID = UUID()
            self.observers[observerID] = continuation
            continuation.yield(allJobs())
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeObserver(id: observerID) }
            }
        }
    }

    private func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func broadcastUpdate() {
        let snapshot = allJobs()
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }
}