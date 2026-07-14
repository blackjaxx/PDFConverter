import AppKit
import Combine
import Foundation
import PDFConverterCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedType: ConversionType = .pdfToPNG
    @Published var inputURLs: [URL] = []
    @Published var outputDirectory: URL?
    @Published var parameters = ConversionParameters()
    @Published var jobs: [ConversionJob] = []
    @Published var toolReport: [(tool: BundledTool, available: Bool, path: String?)] = []
    @Published var deepSeekAPIKeyInput: String = ""
    @Published var deepSeekBaseURL: String = DeepSeekSettings.baseURL
    @Published var deepSeekModel: String = DeepSeekSettings.model
    @Published var isDeepSeekConfigured: Bool = DeepSeekSettings.isConfigured
    @Published private(set) var isOfficeAutomationAvailable: Bool = false
    @Published var showOfficeInstallSheet: Bool = false

    private let registry: EngineRegistry
    private var jobsObserverTask: Task<Void, Never>?
    private var notifiedJobFailures: Set<UUID> = []

    init(registry: EngineRegistry? = nil) {
        self.registry = registry ?? Self.makeDefaultRegistry()
        Task { await bootstrap() }
    }

    deinit { jobsObserverTask?.cancel() }

    static func makeDefaultRegistry() -> EngineRegistry {
        EngineRegistry(engines: [
            PDFKitEngine(), PopplerEngine(), QpdfEngine(), GhostscriptEngine(),
            OfficeAutomationEngine(), TesseractEngine(),
            AppWebKitEngine(), AppLLMEngine()
        ])
    }

    func bootstrap() async {
        let toolsRoot = ToolsBootstrap.toolsRootURL()

        await JobOrchestrator.shared.configure(
            toolsRoot: toolsRoot,
            registry: registry,
            progressHandler: { [weak self] jobID, progress, status in
                self?.handleProgressUpdate(jobID: jobID, progress: progress, status: status)
            }
        )

        jobsObserverTask = Task { [weak self] in
            guard let self else { return }
            for await updatedJobs in await JobOrchestrator.shared.observeJobs() {
                self.jobs = updatedJobs
                self.checkForFailedJobs(in: updatedJobs)
            }
        }

        reloadDeepSeekSettings()
        toolReport = ToolLocator.shared.availabilityReport()
        isOfficeAutomationAvailable = OfficeAvailability.check()

        if !isOfficeAutomationAvailable && (selectedType.category == .officeToPDF || selectedType.category == .pdfToOffice) {
            selectedType = .pdfToPNG
        }

        checkStartupToolAvailability()
        await refreshJobs()
    }

    private func checkStartupToolAvailability() {
        let criticalTools = ["pdftoppm", "pdftotext", "qpdf", "gs", "tesseract"]
        let missing = toolReport
            .filter { criticalTools.contains($0.tool.name) && !$0.available }
            .map { $0.tool.name }
        if !missing.isEmpty {
            ErrorCenter.shared.report(AppError.missingCriticalTools(missing))
        }
    }

    private func checkForFailedJobs(in jobs: [ConversionJob]) {
        let failed = jobs.filter { $0.status == .failed }
        for job in failed where !notifiedJobFailures.contains(job.id) {
            notifiedJobFailures.insert(job.id)
            // v0.4.5：写日志（同时出现在 Console.app 和设置页面日志查看器）
            AppLogger.shared.error(
                "任务失败: \(job.type.displayName)",
                metadata: [
                    "jobID": job.id.uuidString,
                    "error": job.errorMessage ?? "未知错误",
                    "stderr": job.stderrDetails ?? "(无详细信息)"
                ]
            )
            ErrorCenter.shared.report(AppError.jobFailed(
                jobType: job.type.displayName,
                error: job.errorMessage ?? "未知错误",
                details: job.stderrDetails
            ))
        }
    }

    private func handleProgressUpdate(jobID: UUID, progress: Double, status: JobStatus) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].progress = progress
        jobs[index].status = status
    }

    func refreshOfficeAvailability() {
        isOfficeAutomationAvailable = OfficeAvailability.check()
    }

    var groupedTypes: [(ConversionCategory, [ConversionType])] {
        let types = ConversionType.allCases
        return ConversionCategory.allCases.compactMap { cat in
            let items = types.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    var hasOfficeBackendAvailable: Bool { isOfficeAutomationAvailable }

    func isBackendAvailable(for type: ConversionType) -> Bool {
        switch type.category {
        case .officeToPDF, .pdfToOffice: return isOfficeAutomationAvailable
        case .ai: return isDeepSeekConfigured
        default: return true
        }
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = selectedType == .mergePDF
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in self.inputURLs = panel.urls }
        }
    }

    func pickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self.outputDirectory = url }
        }
    }

    // MARK: - v0.4.4 重置与删除功能

    /// 删除单个已选文件
    func removeInputURL(_ url: URL) {
        inputURLs.removeAll { $0 == url }
    }

    /// 清空所有已选文件
    func clearInputURLs() {
        let count = inputURLs.count
        inputURLs = []
        if count > 0 {
            ErrorCenter.shared.reportInfo("已清空 \(count) 个文件")
        }
    }

    /// 清除输出文件夹选择（恢复为默认与源文件同目录）
    func clearOutputDirectory() {
        if outputDirectory != nil {
            outputDirectory = nil
            ErrorCenter.shared.reportInfo("已清除输出文件夹，将使用默认位置")
        }
    }

    /// 重置当前转换类型的所有参数为默认值
    ///
    /// 不同类型有不同的参数，所以基于 `selectedType` 决定重置哪些字段。
    /// 这是细粒度的重置——只重置当前类型用到的参数，避免影响其他类型的设置。
    func resetCurrentParameters() {
        parameters = ConversionParameters()  // 全部重置为默认值
        ErrorCenter.shared.reportInfo("已重置参数为默认值")
    }

    /// 重置整个转换面板状态：文件 + 输出目录 + 参数 + 转换类型。
    ///
    /// 这是"重头来过"按钮。任务队列不会被清空（那是历史记录）。
    func resetConversionPanel() {
        let hadFiles = !inputURLs.isEmpty
        let hadOutput = outputDirectory != nil
        inputURLs = []
        outputDirectory = nil
        parameters = ConversionParameters()
        selectedType = .pdfToPNG
        if hadFiles || hadOutput {
            ErrorCenter.shared.reportInfo("已重置转换面板")
        }
    }

    /// 从队列中移除单个任务（不影响磁盘上的输出文件）
    func removeJob(id: UUID) async {
        await JobOrchestrator.shared.removeJob(id: id)
    }

    /// 清空已完成的任务（不取消正在运行/等待的）
    func clearCompletedJobs() async {
        let removed = await JobOrchestrator.shared.clearCompletedJobs()
        if removed > 0 {
            ErrorCenter.shared.reportInfo("已清除 \(removed) 个已完成任务")
        }
    }

    /// 清空全部任务（包括 pending/running 强制取消）
    func clearAllJobs() async {
        let removed = await JobOrchestrator.shared.clearAllJobs()
        notifiedJobFailures.removeAll()
        if removed > 0 {
            ErrorCenter.shared.reportInfo("已清除 \(removed) 个任务")
        }
    }

    func enqueueConversion() {
        guard !inputURLs.isEmpty else {
            AppLogger.shared.warning("enqueueConversion called with empty inputURLs")
            return
        }

        AppLogger.shared.info(
            "Enqueueing conversion: \(selectedType.displayName)",
            metadata: [
                "type": selectedType.rawValue,
                "fileCount": String(inputURLs.count),
                "outputDir": outputDirectory?.path ?? "(default)"
            ]
        )

        if (selectedType.category == .officeToPDF || selectedType.category == .pdfToOffice)
            && !isOfficeAutomationAvailable {
            AppLogger.shared.warning("Office conversion attempted but no backend available")
            ErrorCenter.shared.report(AppError.missingLibreOffice())
            showOfficeInstallSheet = true
            return
        }

        if selectedType.requiresNetwork && !isDeepSeekConfigured {
            AppLogger.shared.warning("AI conversion attempted but DeepSeek not configured")
            ErrorCenter.shared.report(AppError.deepSeekNotConfigured())
            return
        }

        for url in inputURLs {
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                AppLogger.shared.error(
                    "Input file not readable",
                    metadata: ["path": url.path]
                )
                ErrorCenter.shared.report(AppError.fileReadFailed(
                    path: url.path,
                    error: "文件不存在或无读取权限"
                ))
                return
            }
        }

        let job = ConversionJob(
            type: selectedType,
            inputURLs: inputURLs,
            outputDirectory: outputDirectory,
            parameters: parameters
        )
        Task { await JobOrchestrator.shared.enqueue(job) }
    }

    func refreshJobs() async {
        let list = await JobOrchestrator.shared.allJobs()
        jobs = list
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func engineLabel(for type: ConversionType) -> String {
        registry.engine(for: type)?.kind.rawValue ?? "—"
    }

    var needsDeepSeekConfiguration: Bool {
        selectedType.requiresNetwork && !isDeepSeekConfigured
    }

    func reloadDeepSeekSettings() {
        deepSeekBaseURL = DeepSeekSettings.baseURL
        deepSeekModel = DeepSeekSettings.model
        isDeepSeekConfigured = DeepSeekSettings.isConfigured
        deepSeekAPIKeyInput = ""
    }

    func saveDeepSeekSettings() {
        DeepSeekSettings.baseURL = deepSeekBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        DeepSeekSettings.model = deepSeekModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !deepSeekAPIKeyInput.isEmpty {
            do {
                try DeepSeekSettings.saveAPIKey(deepSeekAPIKeyInput)
            } catch {
                ErrorCenter.shared.reportError(title: "无法保存 API Key", message: error.localizedDescription)
            }
        }
        reloadDeepSeekSettings()
    }

    func clearDeepSeekAPIKey() {
        do {
            try DeepSeekSettings.clearAPIKey()
        } catch {
            ErrorCenter.shared.reportError(title: "无法清除 API Key", message: error.localizedDescription)
        }
        reloadDeepSeekSettings()
    }

    func clearError() {}

    func retryJob(_ job: ConversionJob) {
        let retry = ConversionJob(
            type: job.type,
            inputURLs: job.inputURLs,
            outputDirectory: job.outputDirectory,
            parameters: job.parameters
        )
        Task { await JobOrchestrator.shared.enqueue(retry) }
        ErrorCenter.shared.reportInfo("已重新提交: \(job.type.displayName)")
    }
}

enum OfficeAvailability {
    static let msOfficeBundleIDs = ["com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint"]
    static let iWorkBundleIDs = ["com.apple.iWork.Pages", "com.apple.iWork.Numbers", "com.apple.iWork.Keynote"]

    static func check() -> Bool {
        for bundleID in msOfficeBundleIDs {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil { return true }
        }
        for bundleID in iWorkBundleIDs {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil { return true }
        }
        return ToolLocator.shared.availabilityReport().first { $0.tool.name == "soffice" }?.available == true
    }
}