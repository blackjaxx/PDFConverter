import SwiftUI
import PDFConverterCore

/// 主界面 - v0.4.9 重构版
///
/// 使用 macOS HIG 推荐的多窗格布局：
/// ```
/// ┌──────────────────────────────────────────┐
/// │ NavigationSplitView                       │
/// │ ┌─────────┬──────────────────────────┐    │
/// │ │ Sidebar  │ 主区域                    │    │
/// │ │          │ ├─ 顶部 toolbar          │    │
/// │ │ 分类选择  │ ├─ ConversionPanelView   │    │
/// │ │          │ ↕ 可拖拽 splitter        │    │
/// │ │          │ ├─ JobQueueView (右 dock)│    │
/// │ └─────────┴──────────────────────────┘    │
/// └──────────────────────────────────────────┘
/// ```
///
/// 关键改进：
/// 1. **HSplitView + 可拖拽 splitter** - 用户可调整转换面板和任务队列的宽度
/// 2. **顶部工具栏** - 「开始转换」按钮和批量操作移到顶部，不再滚动
/// 3. **自动适配紧凑模式** - 窗口很窄时任务队列可被隐藏
struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var errorCenter = ErrorCenter.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: 180,
                    ideal: 220,
                    max: 320
                )
        } detail: {
            VStack(spacing: 0) {
                ErrorBannerList(center: errorCenter)

                // HSplitView 提供原生 macOS 拖拽 splitter
                HSplitView {
                    ConversionPanelView()
                        .frame(minWidth: 360, idealWidth: 480)
                        .layoutPriority(1)

                    JobQueueView()
                        .frame(
                            minWidth: 280,
                            idealWidth: 340,
                            maxWidth: 480
                        )
                        .layoutPriority(0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel.selectedType.displayName)
        .navigationSubtitle(viewModel.engineLabel(for: viewModel.selectedType))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // v0.4.9：开始转换按钮移到顶部工具栏
                Button {
                    viewModel.enqueueConversion()
                } label: {
                    Label("开始转换", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.inputURLs.isEmpty || viewModel.needsDeepSeekConfiguration)
                .help("把所有已选文件加入转换队列（Cmd+Enter）")

                // 批量任务操作
                Menu {
                    Button("清空已完成") {
                        Task { await viewModel.clearCompletedJobs() }
                    }
                    .disabled(!viewModel.hasJobsInState(.completed, .failed, .cancelled))

                    Button("清空全部（含运行中）", role: .destructive) {
                        Task { await viewModel.clearAllJobs() }
                    }
                    .disabled(viewModel.jobs.isEmpty)
                } label: {
                    Label("任务操作", systemImage: "checklist")
                }
                .help("任务队列的批量操作")
            }
        }
        .sheet(isPresented: $viewModel.showOfficeInstallSheet) {
            OfficeInstallSheet(isPresented: $viewModel.showOfficeInstallSheet)
        }
    }
}

/// v0.4.9：转换面板 - 顶部 toolbar 在 ContentView，「开始转换」按钮已移走
/// 其他布局保持一致
struct ConversionPanelView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 标题 + 重置按钮（标题 + 描述，更清晰）
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.selectedType.displayName)
                            .font(.title2.bold())
                        Text("引擎: \(viewModel.engineLabel(for: viewModel.selectedType))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showResetConfirm = true
                    } label: {
                        Label("重置", systemImage: "arrow.counterclockwise")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("清空文件、参数、输出文件夹")
                }

                if viewModel.needsDeepSeekConfiguration {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("请先在 设置 → DeepSeek 填写 API Key")
                            .font(.caption)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                }

                DropZoneView()

                if !viewModel.inputURLs.isEmpty {
                    FileListView(
                        urls: viewModel.inputURLs,
                        onRemove: { url in viewModel.removeInputURL(url) },
                        onClearAll: { viewModel.clearInputURLs() }
                    )
                }

                ConversionOptionsView(onReset: { viewModel.resetCurrentParameters() })

                // 输出文件夹区域
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("输出文件夹")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let dir = viewModel.outputDirectory {
                        Text(dir.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(dir.path)
                        Button {
                            viewModel.clearOutputDirectory()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("清除输出文件夹（恢复为默认与源文件同目录）")
                    } else {
                        Text("默认（与源文件相同目录）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        viewModel.pickOutputDirectory()
                    } label: {
                        Text("选择…")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 6)
            }
            .padding(20)
        }
        .confirmationDialog(
            "重置整个转换面板？",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("重置", role: .destructive) {
                viewModel.resetConversionPanel()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清空：\n• 已选文件\n• 输出文件夹选择\n• 参数设置\n• 转换类型\n\n任务队列不会被清空。")
        }
    }
}

/// v0.4.9 文件列表：色彩更柔和、间距更紧凑
struct FileListView: View {
    let urls: [URL]
    let onRemove: (URL) -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("已选文件 (\(urls.count))")
                    .font(.headline)
                Spacer()
                Button {
                    onClearAll()
                } label: {
                    Label("清空", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("清空所有已选文件")
            }
            ForEach(urls, id: \.path) { url in
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.tint)
                        .font(.caption)
                    Text(url.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.path)
                    Spacer()
                    Button {
                        onRemove(url)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("从列表中移除（不删除磁盘文件）")
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
    }
}

struct OfficeInstallSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.badge.gearshape")
                    .font(.title)
                    .foregroundStyle(.tint)
                Text("安装 Office 文档转换组件")
                    .font(.title2.bold())
            }

            Text("PDF Converter 支持三种 Office 文档转换方式，按推荐顺序：")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                installOptionRow(
                    icon: "checkmark.seal.fill", iconColor: .green,
                    title: "Microsoft Office 365", subtitle: "原生导出，质量最高",
                    detail: "如果已安装 Microsoft Word/Excel/PowerPoint，\n应用会自动调用它们，无需额外操作。"
                )
                installOptionRow(
                    icon: "doc.text.fill", iconColor: .blue,
                    title: "Apple iWork（Pages/Numbers/Keynote）", subtitle: "系统自带，免费",
                    detail: "如果已安装 iWork 套件，应用会自动调用它们。"
                )
                installOptionRow(
                    icon: "arrow.down.circle.fill", iconColor: .orange,
                    title: "LibreOffice", subtitle: "免费开源，约 300MB",
                    detail: "如果未安装任何 Office 软件，可下载 LibreOffice。\n终端命令：brew install --cask libreoffice",
                    action: {
                        Button("打开下载页") {
                            if let url = URL(string: "https://www.libreoffice.org/download/") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                )
            }

            Divider()

            HStack {
                Spacer()
                Button("关闭") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 540)
    }

    @ViewBuilder
    private func installOptionRow<Content: View>(
        icon: String, iconColor: Color,
        title: String, subtitle: String,
        detail: String,
        @ViewBuilder action: () -> Content = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if Content.self != EmptyView.self {
                    action()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.tertiary))
    }
}