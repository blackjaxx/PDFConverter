import Foundation

public typealias JobProgressHandler = @Sendable (UUID, Double, JobStatus) -> Void

/// Queues and executes conversion jobs with bounded concurrency.
public actor JobOrchestrator {
    public static let shared = JobOrchestrator()

    private let registry: EngineRegistry
    private let maxConcurrent: Int
    private var queue: [ConversionJob] = []
    private var running = 0
    private var jobsByID: [UUID: ConversionJob] = [:]
    private var progressHandler: JobProgressHandler?
    private var toolsRoot: URL?

    public init(registry: EngineRegistry = .shared, maxConcurrent: Int = 2) {
        self.registry = registry
        self.maxConcurrent = max(1, maxConcurrent)
    }

    public func configure(toolsRoot: URL?, progressHandler: JobProgressHandler? = nil) {
        self.toolsRoot = toolsRoot
        self.progressHandler = progressHandler
        ToolLocator.shared.configure(toolsRoot: toolsRoot)
    }

    public func enqueue(_ job: ConversionJob) {
        var j = job
        j.status = .pending
        jobsByID[j.id] = j
        queue.append(j)
        Task { await pump() }
    }

    public func allJobs() -> [ConversionJob] {
        jobsByID.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func cancel(id: UUID) {
        guard var job = jobsByID[id], job.status == .pending || job.status == .running else { return }
        job.status = .cancelled
        jobsByID[id] = job
        queue.removeAll { $0.id == id }
        notify(job)
    }

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
        await pump()
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
        progressHandler?(job.id, job.progress, job.status)
    }
}
