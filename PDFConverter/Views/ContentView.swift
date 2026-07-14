import SwiftUI
import PDFConverterCore

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var errorCenter = ErrorCenter.shared

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                ErrorBannerList(center: errorCenter)

                HStack(spacing: 0) {
                    ConversionPanelView()
                        .frame(minWidth: 380)
                    Divider()
                    JobQueueView()
                        .frame(minWidth: 320)
                }
            }
        }
        .navigationTitle("PDF Converter")
        .sheet(isPresented: $viewModel.showOfficeInstallSheet) {
            OfficeInstallSheet(isPresented: $viewModel.showOfficeInstallSheet)
        }
    }
}

/// v0.4.4：转换面板完整重写，添加：
/// - 标题右侧「重置全部」按钮
/// - 文件列表带删除按钮和清空按钮
/// - 输出文件夹带清除按钮
struct ConversionPanelView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题 + 重置全部按钮
                HStack {
                    Text(viewModel.selectedType.displayName)
                        .font(.title2.bold())
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

                Text("引擎: \(viewModel.engineLabel(for: viewModel.selectedType))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DropZoneView()

                if !viewModel.inputURLs.isEmpty {
                    FileListView(
                        urls: viewModel.inputURLs,
                        onRemove: { url in viewModel.removeInputURL(url) },
                        onClearAll: { viewModel.clearInputURLs() }
                    )
                }

                ConversionOptionsView(onReset: { viewModel.resetCurrentParameters() })

                // 输出文件夹区域：带"清除"按钮
                HStack {
                    Button("选择输出文件夹") { viewModel.pickOutputDirectory() }
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
                        Text("默认：与源文件相同目录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: { viewModel.enqueueConversion() }) {
                    Label("开始转换", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.inputURLs.isEmpty || viewModel.needsDeepSeekConfiguration)
            }
            .padding(24)
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

/// v0.4.4：文件列表 - 每个文件独立删除按钮 + 顶部清空全部按钮
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
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.path)
                    Spacer()
                    Button {
                        onRemove(url)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("从列表中移除（不删除磁盘文件）")
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct OfficeInstallSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.badge.gearshape")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("安装 Office 文档转换组件")
                    .font(.title2.bold())
            }

            Text("PDF Converter 支持三种 Office 文档转换方式，按推荐顺序：")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                OptionRow(
                    icon: "checkmark.seal.fill", iconColor: .green,
                    title: "Microsoft Office 365", subtitle: "原生导出，质量最高",
                    detail: "如果已安装 Microsoft Word/Excel/PowerPoint，\n应用会自动调用它们，无需额外操作。"
                )
                OptionRow(
                    icon: "doc.text.fill", iconColor: .blue,
                    title: "Apple iWork（Pages/Numbers/Keynote）", subtitle: "系统自带，免费",
                    detail: "如果已安装 iWork 套件，应用会自动调用它们。"
                )
                OptionRow(
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
}

struct OptionRow<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let detail: String
    let action: (() -> Content)?

    init(icon: String, iconColor: Color, title: String, subtitle: String, detail: String,
         @ViewBuilder action: @escaping () -> Content = { EmptyView() }) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.action = action
    }

    var body: some View {
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
                if let action = action { action() }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
    }
}