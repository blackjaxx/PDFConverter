import AppKit
import Combine
import Foundation
import PDFConverterCore

/// 这是应用的**核心 ViewModel**。
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
    /// v0.4.3：是否显示 Office 安装指引 sheet
    @Published var showOfficeInstallSheet: Bool = false

    private let registry: EngineRegistry
    private var jobsObserverTask: Task<Void, Never>?

    init(registry: EngineRegistry? = nil) {
        self.registry = registry ?? Self.makeDefaultRegistry()
        Task {
            await bootstrap()
        }
    }

    deinit {
        jobsObserverTask?.cancel()
    }

    static func makeDefaultRegistry() -> EngineRegistry {
        EngineRegistry(engines: [
            PDFKitEngine(),
            PopplerEngine(),
            QpdfEngine(),
            GhostscriptEngine(),
            OfficeAutomationEngine(),
            TesseractEngine(),
            AppWebKitEngine(),
            AppLLMEngine()
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

        // v0.4.3：启动时检测关键工具，缺失则提示用户
        checkStartupToolAvailability()

        await refreshJobs()
    }

    /// v0.4.3：检测启动时关键工具是否就绪
    ///
    /// - 检查 poppler/qpdf/ghostscript/tesseract 这些核心 CLI 工具
    /// - 缺失的工具会通过 ErrorCenter 推送警告横幅
    /// - 用户可以选择"查看详情"跳到设置页面
    private func checkStartupToolAvailability() {
        let criticalTools = ["pdftoppm", "pdftotext", "qpdf", "gs", "tesseract"]
        let missing = toolReport
            .filter { criticalTools.contains($0.tool.name) && !$0.available }
            .map { $0.tool.name }

        if !missing.isEmpty {
            ErrorCenter.shared.report(AppError.missingCriticalTools(missing))
        }
    }

    /// v0.4.3：检查任务列表中的失败任务，自动推送到错误中心。
    /// - 只推送一次（每个失败任务只推送一次，避免重复通知）
    /// - 已通知过的任务 ID 用 notifiedJobFailures 集合追踪
    private var notifiedJobFailures: Set<UUID> = []

    private func checkForFailedJobs(in jobs: [ConversionJob]) {
        let failed = jobs.filter { $0.status == .failed }
        for job in failed where !notifiedJobFailures.contains(job.id) {
            notifiedJobFailures.insert(job.id)
            let error = AppError.jobFailed(
                jobType: job.type.displayName,
                error: job.errorMessage ?? "未知错误",
                details: job.stderrDetails
            )
            ErrorCenter.shared.report(error)
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

    var hasOfficeBackendAvailable: Bool {
        isOfficeAutomationAvailable
    }

    func isBackendAvailable(for type: ConversionType) -> Bool {
        switch type.category {
        case .officeToPDF, .pdfToOffice:
            return isOfficeAutomationAvailable
        case .ai:
            return isDeepSeekConfigured
        default:
            return true
        }
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = selectedType == .mergePDF
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in
                self.inputURLs = panel.urls
            }
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

    /// v0.4.3：enqueue 前 pre-flight 检查
    ///
    /// 在任务真正提交到 JobOrchestrator 之前，先检查：
    /// 1. 输入文件是否可读
    /// 2. Office 转换是否有后端可用
    /// 3. AI 转换是否已配置
    ///
    /// 任何检查失败都会通过 ErrorCenter 推送警告横幅，不会让用户看到任务"失败"。
    func enqueueConversion() {
        guard !inputURLs.isEmpty else { return }

        // Pre-flight: Office 后端可用性
        if (selectedType.category == .officeToPDF || selectedType.category == .pdfToOffice)
            && !isOfficeAutomationAvailable {
            ErrorCenter.shared.report(AppError.missingLibreOffice())
            showOfficeInstallSheet = true
            return
        }

        // Pre-flight: AI 配置
        if selectedType.requiresNetwork && !isDeepSeekConfigured {
            ErrorCenter.shared.report(AppError.deepSeekNotConfigured())
            return
        }

        // Pre-flight: 输入文件可读性
        for url in inputURLs {
            guard FileManager.default.isReadableFile(atPath: url.path) else {
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
        Task {
            await JobOrchestrator.shared.enqueue(job)
        }
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
                ErrorCenter.shared.reportError(
                    title: "无法保存 API Key",
                    message: error.localizedDescription
                )
            }
        }
        reloadDeepSeekSettings()
    }

    func clearDeepSeekAPIKey() {
        do {
            try DeepSeekSettings.clearAPIKey()
        } catch {
            ErrorCenter.shared.reportError(
                title: "无法清除 API Key",
                message: error.localizedDescription
            )
        }
        reloadDeepSeekSettings()
    }

    func clearError() {
        // 向后兼容：旧的 errorMessage 字段，现已废弃，统一用 ErrorCenter
    }

    /// v0.4.3：重试失败的任务
    func retryJob(_ job: ConversionJob) {
        let retry = ConversionJob(
            type: job.type,
            inputURLs: job.inputURLs,
            outputDirectory: job.outputDirectory,
            parameters: job.parameters
        )
        Task {
            await JobOrchestrator.shared.enqueue(retry)
        }
        ErrorCenter.shared.reportInfo("已重新提交: \(job.type.displayName)")
    }
}

// MARK: - OfficeAvailability

enum OfficeAvailability {
    static let msOfficeBundleIDs = [
        "com.microsoft.Word",
        "com.microsoft.Excel",
        "com.microsoft.Powerpoint"
    ]

    static let iWorkBundleIDs = [
        "com.apple.iWork.Pages",
        "com.apple.iWork.Numbers",
        "com.apple.iWork.Keynote"
    ]

    static func check() -> Bool {
        for bundleID in msOfficeBundleIDs {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
                return true
            }
        }
        for bundleID in iWorkBundleIDs {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
                return true
            }
        }
        return ToolLocator.shared.availabilityReport().first { $0.tool.name == "soffice" }?.available == true
    }
}