import SwiftUI
import PDFConverterCore
import AppKit

/// 偏好设置窗口。
///
/// v0.5.0 新增「存储与卸载」区域：明确告诉用户
/// - 工具装在哪里（App 包内，不写系统目录）
/// - 卸载是否有残留（无，拖废纸篓即彻底删除）
/// - 临时文件在哪、如何一键清理
/// - DeepSeek Key 存于钥匙串、如何清除
struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var logStore = LogStore.shared
    @State private var showLogs = false
    @State private var tempFileCount: Int? = nil
    @State private var isCleaningTemp = false

    var body: some View {
        Form {
            // DeepSeek 配置
            Section {
                Link("获取 API Key", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                TextField("API Base URL", text: $viewModel.deepSeekBaseURL)
                TextField("模型", text: $viewModel.deepSeekModel)
                    .help("默认 deepseek-chat")
                SecureField(
                    viewModel.isDeepSeekConfigured ? "API Key（已保存，输入新 Key 可覆盖）" : "API Key",
                    text: $viewModel.deepSeekAPIKeyInput
                )
                HStack {
                    Button("保存") { viewModel.saveDeepSeekSettings() }
                    Button("清除 Key", role: .destructive) { viewModel.clearDeepSeekAPIKey() }
                }
                HStack {
                    Image(systemName: viewModel.isDeepSeekConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(viewModel.isDeepSeekConfigured ? .green : .secondary)
                    Text(viewModel.isDeepSeekConfigured ? "DeepSeek 已配置" : "未配置")
                        .font(.caption)
                }
                Text("仅在你执行 AI 转换时联网；Key 保存在系统钥匙串，卸载前可用上方按钮清除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("DeepSeek（云端 AI）")
            }

            // 离线工具链
            Section {
                Text("所有 CLI 工具已内置在 App 包内（PDFConverter.app/Contents/Resources/tools/），无需额外下载安装。若 App 内工具不可用，会自动回退到 Homebrew 安装的系统版本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(viewModel.toolReport.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Image(systemName: item.available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.available ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(item.tool.name)
                            if let path = item.path {
                                Text(path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if !viewModel.isOfficeAutomationAvailable {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Office 转换后端均不可用")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("未检测到 Microsoft Office、Apple iWork 或 LibreOffice。\n这些是独立的第三方软件，本应用不会代为下载；安装任一套件后即可启用 Office 文档转换。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("离线工具链")
            }

            // v0.5.0：存储与卸载说明
            Section {
                storageRow(
                    icon: "shippingbox.fill", color: .blue,
                    title: "内置工具",
                    detail: "随 App 一起安装在 PDFConverter.app 包内部，不写入系统目录。"
                )
                storageRow(
                    icon: "trash.circle.fill", color: .green,
                    title: "卸载方式",
                    detail: "把 PDFConverter.app 拖入废纸篓即彻底删除，无任何系统残留、无 Launch Agent、无后台服务。"
                )
                storageRow(
                    icon: "key.fill", color: .orange,
                    title: "钥匙串",
                    detail: "仅当你配置过 DeepSeek 时存在一条 API Key。可在上方「清除 Key」按钮删除。"
                )

                // 临时文件 + 一键清理
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.purple)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("临时文件")
                            .font(.callout)
                        Text(tempSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        cleanTempFiles()
                    } label: {
                        if isCleaningTemp {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("立即清理")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCleaningTemp)
                }
            } header: {
                Text("存储与卸载")
            }

            // v0.4.5：日志查看器入口
            Section {
                HStack {
                    Text("已记录 \(logStore.entries.count) 条日志")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("查看日志") {
                        showLogs = true
                    }
                    Button("打开 Console.app") {
                        AppLogger.shared.revealLogFileInFinder()
                    }
                    .help("macOS 统一日志系统，可按 subsystem: com.local.pdfconverter 过滤")
                }
            } header: {
                Text("调试日志")
            }

            // 分发信息
            Section {
                LabeledContent("渠道", value: "直接分发（非 Mac App Store）")
                LabeledContent("沙盒", value: "已关闭，可调用捆绑 CLI")
                LabeledContent("版本", value: PDFConverterCore.version)
            } header: {
                Text("关于")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .sheet(isPresented: $showLogs) {
            LogViewerSheet(isPresented: $showLogs)
        }
        .onAppear { refreshTempCount() }
    }

    // MARK: - 临时文件管理

    private var tempSummary: String {
        guard let count = tempFileCount else {
            return "位于系统临时目录（$TMPDIR/PDFConverter/），macOS 会自动清理。"
        }
        if count == 0 {
            return "当前无残留（0 项）。macOS 也会定期自动清理该目录。"
        }
        return "当前有 \(count) 个历史任务目录。macOS 重启时也会自动清理。"
    }

    private func refreshTempCount() {
        tempFileCount = TempCleaner.countLeftoverJobs()
    }

    private func cleanTempFiles() {
        isCleaningTemp = true
        Task {
            let removed = TempCleaner.cleanAll()
            await MainActor.run {
                isCleaningTemp = false
                tempFileCount = TempCleaner.countLeftoverJobs()
                ErrorCenter.shared.reportInfo(
                    removed > 0 ? "已清理 \(removed) 个临时任务目录" : "没有需要清理的临时文件"
                )
            }
        }
    }

    // MARK: - 行组件

    @ViewBuilder
    private func storageRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// v0.5.0：临时文件清理工具。
///
/// 转换过程的中间文件存放在 `$TMPDIR/PDFConverter/<job-uuid>/`，
/// JobOrchestrator 在任务结束时会自动删除自己的工作目录；
/// 但如果 App 意外退出（崩溃/强杀），可能留下残留。
/// macOS 重启会清空整个 TMPDIR，这里提供手动立即清理的入口。
enum TempCleaner {
    static var tempRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFConverter", isDirectory: true)
    }

    /// 统计残留的任务工作目录数量（不存在时返回 0）
    static func countLeftoverJobs() -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: tempRoot, includingPropertiesForKeys: nil
        ) else { return 0 }
        return items.count
    }

    /// 清理所有残留目录，返回删除的数量
    @discardableResult
    static func cleanAll() -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil) else {
            return 0
        }
        var removed = 0
        for item in items {
            if (try? fm.removeItem(at: item)) != nil {
                removed += 1
            }
        }
        return removed
    }
}

/// 日志查看器 Sheet。
struct LogViewerSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var logStore = LogStore.shared
    @State private var filterLevel: AppLogger.LogEntry.LogLevel? = nil
    @State private var searchText: String = ""

    var filteredEntries: [AppLogger.LogEntry] {
        logStore.entries.filter { entry in
            // 过滤级别
            if let level = filterLevel, entry.level != level { return false }
            // 搜索关键字
            if !searchText.isEmpty {
                let inMessage = entry.message.localizedCaseInsensitiveContains(searchText)
                let inMetadata = entry.metadata.values.contains { $0.localizedCaseInsensitiveContains(searchText) }
                if !inMessage && !inMetadata { return false }
            }
            return true
        }.reversed() // 最新的在最上面
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("应用日志（最近 \(logStore.entries.count) 条）")
                    .font(.headline)
                Spacer()
                Picker("", selection: $filterLevel) {
                    Text("全部").tag(AppLogger.LogEntry.LogLevel?.none)
                    Text("🔵 Info").tag(AppLogger.LogEntry.LogLevel?.some(.info))
                    Text("🟠 Warning").tag(AppLogger.LogEntry.LogLevel?.some(.warning))
                    Text("🔴 Error").tag(AppLogger.LogEntry.LogLevel?.some(.error))
                    Text("⚫ Debug").tag(AppLogger.LogEntry.LogLevel?.some(.debug))
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索消息或元数据...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filteredEntries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text(searchText.isEmpty ? "暂无日志" : "无匹配日志")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    } else {
                        ForEach(filteredEntries) { entry in
                            LogRow(entry: entry)
                        }
                    }
                }
            }
            .frame(maxHeight: 500)

            Divider()

            HStack {
                Button("清空缓冲区") {
                    logStore.clear()
                }
                Button("复制全部到剪贴板") {
                    let text = AppLogger.shared.exportAsString()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Spacer()
                Button("关闭") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 720, height: 560)
    }
}

/// 单条日志行
struct LogRow: View {
    let entry: AppLogger.LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                Text(entry.level.rawValue.uppercased())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(levelColor(entry.level))
                    .frame(width: 60, alignment: .leading)
                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !entry.metadata.isEmpty {
                HStack {
                    Spacer().frame(width: 70 + 60 + 16)
                    Text(entry.metadata.map { "\($0.key): \($0.value)" }.joined(separator: " · "))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.04))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.gray.opacity(0.1)),
            alignment: .bottom
        )
    }

    private func levelColor(_ level: AppLogger.LogEntry.LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}