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

    /// 引擎注册表：维护「转换类型 → 引擎」的映射关系，是核心的路由层
    private let registry: EngineRegistry
    /// 定时刷新队列的后台任务引用
    private var refreshTask: Task<Void, Never>?

    init(registry: EngineRegistry? = nil) {
        self.registry = registry ?? Self.makeDefaultRegistry()
        Task {
            do {
                await bootstrap()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
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
            LibreOfficeEngine(),
            TesseractEngine(),
            AppWebKitEngine(),
            AppLLMEngine()
        ])
    }

    /// 应用启动时的初始化流程：
    /// 1. 定位 Bundle 内的工具目录，配置 JobOrchestrator
    /// 2. 从 Keychain/UserDefaults 加载 DeepSeek 设置
    /// 3. 扫描并报告离线 CLI 工具的可用性状态
    /// 4. 从 JobOrchestrator 获取初始任务列表
    func bootstrap() async {
        let toolsRoot = ToolsBootstrap.toolsRootURL()
        await JobOrchestrator.shared.configure(toolsRoot: toolsRoot, registry: registry)
        reloadDeepSeekSettings()
        toolReport = ToolLocator.shared.availabilityReport()
        await refreshJobs()
    }

    /// 将转换类型按 `ConversionCategory` 分组，供侧边栏使用。
    /// 例如 `.pdfToImage` 分类下有 `.pdfToPNG`、`.pdfToJPEG` 等具体类型。
    var groupedTypes: [(ConversionCategory, [ConversionType])] {
        let types = ConversionType.allCases
        return ConversionCategory.allCases.compactMap { cat in
            let items = types.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
        }
    }

    /// 使用 `NSOpenPanel` 打开系统文件选择对话框。
    /// `allowsMultipleSelection` 在合并 PDF 模式下允许多选（因为合并需要多个文件），
    /// 其他模式下仅单选。
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
    /// 支持新建目录（`canCreateDirectories = true`）。
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
            await refreshJobs()
        }
    }

    /// 从 `JobOrchestrator` 获取最新的完整任务列表，
    /// 并更新 `jobs` 属性以刷新 UI。
    func refreshJobs() async {
        let list = await JobOrchestrator.shared.allJobs()
        jobs = list
    }

    /// 在 Finder 中定位并高亮显示给定的文件。
    /// `activateFileViewerSelecting` 会打开一个新 Finder 窗口并选中目标文件。
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 根据转换类型查找对应的引擎名称（如 "PDFKit"、"Poppler"），
    /// 在转换面板中显示给用户，让用户知道当前使用的底层工具。
    func engineLabel(for type: ConversionType) -> String {
        registry.engine(for: type)?.kind.rawValue ?? "—"
    }

    /// 判断当前选中的转换类型是否需要联网（AI 功能），
    /// 且 DeepSeek 尚未配置。用于禁用「开始转换」按钮并显示提示。
    var needsDeepSeekConfiguration: Bool {
        selectedType.requiresNetwork && !isDeepSeekConfigured
    }

    /// 从 `DeepSeekSettings` 重新读取配置，
    /// 同步到 ViewModel 的 `@Published` 属性。
    func reloadDeepSeekSettings() {
        deepSeekBaseURL = DeepSeekSettings.baseURL
        deepSeekModel = DeepSeekSettings.model
        isDeepSeekConfigured = DeepSeekSettings.isConfigured
        deepSeekAPIKeyInput = ""
    }

    /// 保存 DeepSeek 配置：BaseURL 和模型写入 `UserDefaults`，
    /// API Key 写入系统 Keychain（安全存储）。
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