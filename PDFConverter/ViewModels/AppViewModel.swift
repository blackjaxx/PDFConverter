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

    private let registry: EngineRegistry
    private var refreshTask: Task<Void, Never>?

    init(registry: EngineRegistry? = nil) {
        self.registry = registry ?? Self.makeDefaultRegistry()
        Task { await bootstrap() }
    }

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

    func bootstrap() async {
        let toolsRoot = ToolsBootstrap.toolsRootURL()
        await JobOrchestrator.shared.configure(toolsRoot: toolsRoot, registry: registry) { [weak self] _, _, _ in
            Task { @MainActor in self?.refreshJobs() }
        }
        reloadDeepSeekSettings()
        toolReport = ToolLocator.shared.availabilityReport()
        refreshJobs()
    }

    var groupedTypes: [(ConversionCategory, [ConversionType])] {
        let types = ConversionType.allCases
        return ConversionCategory.allCases.compactMap { cat in
            let items = types.filter { $0.category == cat }
            return items.isEmpty ? nil : (cat, items)
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

    func refreshJobs() async {
        let list = await JobOrchestrator.shared.allJobs()
        jobs = list
    }

    private func refreshJobs() {
        refreshTask?.cancel()
        refreshTask = Task { await refreshJobs() }
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
            try? DeepSeekSettings.saveAPIKey(deepSeekAPIKeyInput)
        }
        reloadDeepSeekSettings()
    }

    func clearDeepSeekAPIKey() {
        try? DeepSeekSettings.clearAPIKey()
        reloadDeepSeekSettings()
    }
}
