import SwiftUI
import PDFConverterCore
import AppKit

/// 偏好设置窗口。
///
/// v0.4.5 新增「日志」区域：可在 App 内查看最近 500 条应用日志，
/// 无需打开 Console.app。
struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var logStore = LogStore.shared
    @State private var showLogs = false

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
                Text("仅在你执行 AI 转换时联网；Key 保存在系统钥匙串。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("DeepSeek（云端 AI）")
            }

            // 离线工具链
            Section {
                Text("应用从 `Contents/Resources/tools` 加载 CLI，也可回退到系统 PATH（Homebrew 等）。")
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
                        Text("未检测到 Microsoft Office、Apple iWork 或 LibreOffice。\n请安装任一 Office 套件以启用 Office 文档转换。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("离线工具链")
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
            } header: {
                Text("分发")
            }

            Section {
                LabeledContent("版本", value: PDFConverterCore.version)
            } header: {
                Text("关于")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .sheet(isPresented: $showLogs) {
            LogViewerSheet(isPresented: $showLogs)
        }
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
        .frame(width: 800, height: 700)
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