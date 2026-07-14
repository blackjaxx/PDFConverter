import AppKit
import Combine
import Foundation
import PDFConverterCore

/// 这是应用的**核心 ViewModel**，遵循 MVVM（Model-View-ViewModel）架构模式。
///
/// 在 MVVM 中，ViewModel 的角色是：
/// - **持有应用状态**：所有 UI 关心的数据都存放在这里
/// - **暴露操作接口**：视图层只调用 ViewModel 的方法，不直接操作数据
/// - **协调业务逻辑**：连接引擎注册表、任务编排器、工具定位器等多个底层模块
///
/// `@MainActor` 保证所有 `@Published` 属性的更新都在主线程上，
/// 避免 UI 更新时出现线程不安全的问题。
@MainActor
final class AppViewModel: ObservableObject {
    /// 当前选中的转换类型（用于侧边栏和转换面板联动）
    @Published var selectedType: ConversionType = .pdfToPNG
    /// 用户选择的输入文件列表
    @Published var inputURLs: [URL] = []
    /// 用户指定的输出目录，为 nil 时表示使用源文件所在目录
    @Published var outputDirectory: URL?
    /// 所有转换参数（DPI、压缩档位、密码等），绑定到 ConversionOptionsView
    @Published var parameters = ConversionParameters()
    /// 当前所有转换任务，绑定到 JobQueueView
    @Published var jobs: [ConversionJob] = []
    /// 离线工具链的可用性报告，绑定到 SettingsView 的工具链列表
    @Published var toolReport: [(tool: BundledTool, available: Bool, path: String?)] = []
    /// DeepSeek API Key 输入框的双向绑定值（仅用于输入，不直接存储）
    @Published var deepSeekAPIKeyInput: String = ""
    /// DeepSeek API 地址，默认 `https://api.deepseek.com`
    @Published var deepSeekBaseURL: String = DeepSeekSettings.baseURL
    /// DeepSeek 模型名称，默认 `deepseek-chat`
    @Published var deepSeekModel: String = DeepSeekSettings.model
    /// 标记 DeepSeek 是否已配置完成（API Key 已保存在 Keychain 中）
    @Published var isDeepSeekConfigured: Bool = DeepSeekSettings.isConfigured
    /// 全局错误信息，非 nil 时 ContentView 顶部会显示红色错误横幅
    @Published var errorMessage: String?
    /// Office 自动化引擎可用性（缓存），启动时检测一次
    @Published private(set) var isOfficeAutomationAvailable: Bool = false

    /// 引擎注册表：维护「转换类型 → 引擎」的映射关系，是核心的路由层
    private let registry: EngineRegistry
    /// 订阅 JobOrchestrator 任务状态变化的 Task
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

    /// 组装完整的引擎注册表：包含本地 CLI 引擎（PDFKit、Poppler、Qpdf 等）
    /// 和 App 层引擎（WebKit、LLM）。引擎按优先级排列，JobOrchestrator
    /// 会按顺序查找第一个支持目标转换类型的引擎。
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

    /// 应用启动时的初始化流程：
    /// 1. 定位 Bundle 内的工具目录，配置 JobOrchestrator
    /// 2. **注册 progressHandler**（修复 v0.4.2：原来没注册，进度条永远不动）
    /// 3. **订阅 JobOrchestrator 的 AsyncStream**（修复：UI 自动响应状态变化）
    /// 4. 从 Keychain/UserDefaults 加载 DeepSeek 设置
    /// 5. 扫描并报告离线 CLI 工具的可用性状态
    func bootstrap() async {
        let toolsRoot = ToolsBootstrap.toolsRootURL()

        // 关键修复（v0.4.2）：传入 progressHandler，让进度回调能到达 UI
        await JobOrchestrator.shared.configure(
            toolsRoot: toolsRoot,
            registry: registry,
            progressHandler: { [weak self] jobID, progress, status in
                // 这个闭包被 MainActor 隔离（@MainActor @Sendable）
                self?.handleProgressUpdate(jobID: jobID, progress: progress, status: status)
            }
        )

        // 关键修复（v0.4.2）：订阅 JobOrchestrator 的 AsyncStream，
        // 任务状态变化时自动更新 jobs 数组
        jobsObserverTask = Task { [weak self] in
            guard let self else { return }
            for await updatedJobs in await JobOrchestrator.shared.observeJobs() {
                self.jobs = updatedJobs
            }
        }

        reloadDeepSeekSettings()
        toolReport = ToolLocator.shared.availabilityReport()
        isOfficeAutomationAvailable = OfficeAvailability.check()

        if !isOfficeAutomationAvailable && (selectedType.category == .officeToPDF || selectedType.category == .pdfToOffice) {
            selectedType = .pdfToPNG
        }

        await refreshJobs()
    }

    /// 处理 JobOrchestrator 的进度回调。
    ///
    /// 这个方法在主线程上调用（@MainActor）。
    /// 更新对应任务在 jobs 数组中的状态，触发 SwiftUI 自动重渲染。
    private func handleProgressUpdate(jobID: UUID, progress: Double, status: JobStatus) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].progress = progress
        jobs[index].status = status
    }

    /// 重新检测 Office 可用性（在用户安装新软件后调用）。
    func refreshOfficeAvailability() {
        isOfficeAutomationAvailable = OfficeAvailability.check()
    }

    /// 将转换类型按 `ConversionCategory` 分组，供侧边栏使用。
    ///
    /// 关键行为变更（v0.4.1）：Office 分类现在**始终显示**，即使所有 Office
    /// 后端都不可用。原因：
    /// - 旧行为会在没有任何 Office 后端时隐藏整个分类，用户根本不知道有这功能
    /// - 新行为：分类始终可见，侧边栏内每个 Office 类型会显示「需安装」徽章
    ///
    /// 这种设计更符合「告知用户能做什么」的可用性原则——而不只是隐藏不可用项。
    var groupedTypes: [(ConversionCategory, [ConversionType])] {
        let types = ConversionType.allCases
        return ConversionCategory.allCases.compactMap { cat in
            let items = types.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    /// Office 分类在当前环境下是否可执行实际转换。
    var hasOfficeBackendAvailable: Bool {
        isOfficeAutomationAvailable
    }

    /// 检查某个 ConversionType 在当前环境下是否有可用的后端。
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

    /// 使用 `NSOpenPanel` 打开系统文件选择对话框。
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

    /// 使用 `NSOpenPanel` 打开系统目录选择对话框。
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

    /// 创建 `ConversionJob` 并提交到 `JobOrchestrator` 的异步任务队列。
    /// JobOrchestrator 负责按 FIFO 顺序调度任务、匹配引擎并执行转换。
    ///
    /// 关键修复（v0.4.2）：不再手动调用 refreshJobs()，因为已经通过
    /// AsyncStream 订阅了状态变化。
    func enqueueConversion() {
        guard !inputURLs.isEmpty else { return }
        let job = ConversionJob(
            type: selectedType,
            inputURLs: inputURLs,
            outputDirectory: outputDirectory,
            parameters: parameters
        )
        Task {
            await JobOrchestrator.shared.enqueue(job)
            // AsyncStream 会自动推送状态更新，无需手动 refreshJobs()
        }
    }

    /// 从 `JobOrchestrator` 获取最新的完整任务列表。
    ///
    /// v0.4.2：此方法保留为手动刷新入口，但正常情况下 UI 通过 AsyncStream
    /// 自动更新，无需主动调用。
    func refreshJobs() async {
        let list = await JobOrchestrator.shared.allJobs()
        jobs = list
    }

    /// 在 Finder 中定位并高亮显示给定的文件。
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 根据转换类型查找对应的引擎名称。
    func engineLabel(for type: ConversionType) -> String {
        registry.engine(for: type)?.kind.rawValue ?? "—"
    }

    /// 判断当前选中的转换类型是否需要联网（AI 功能），
    /// 且 DeepSeek 尚未配置。用于禁用「开始转换」按钮并显示提示。
    var needsDeepSeekConfiguration: Bool {
        selectedType.requiresNetwork && !isDeepSeekConfigured
    }

    /// 从 `DeepSeekSettings` 重新读取配置。
    func reloadDeepSeekSettings() {
        deepSeekBaseURL = DeepSeekSettings.baseURL
        deepSeekModel = DeepSeekSettings.model
        isDeepSeekConfigured = DeepSeekSettings.isConfigured
        deepSeekAPIKeyInput = ""
    }

    /// 保存 DeepSeek 配置。
    func saveDeepSeekSettings() {
        DeepSeekSettings.baseURL = deepSeekBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        DeepSeekSettings.model = deepSeekModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !deepSeekAPIKeyInput.isEmpty {
            do {
                try DeepSeekSettings.saveAPIKey(deepSeekAPIKeyInput)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        reloadDeepSeekSettings()
    }

    /// 清除 Keychain 中保存的 DeepSeek API Key。
    func clearDeepSeekAPIKey() {
        do {
            try DeepSeekSettings.clearAPIKey()
        } catch {
            errorMessage = error.localizedDescription
        }
        reloadDeepSeekSettings()
    }

    /// 清除当前错误信息，错误横幅随之消失。
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - OfficeAvailability

/// Office 后端可用性检测（独立为 enum，避免每次 SwiftUI body 重新计算都调用 NSWorkspace）。
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