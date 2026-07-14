import SwiftUI
import PDFConverterCore

/// 应用的主界面，使用 `NavigationSplitView` 实现三栏布局：
/// - **左侧边栏**：显示按分类分组的转换类型列表
/// - **中间转换面板**：文件选择、参数设置、开始转换按钮
/// - **右侧任务队列**：显示所有转换任务的状态和结果
///
/// `NavigationSplitView` 是 macOS 上最经典的布局模式（类似 Finder），
/// 自动支持侧边栏收折和窗口大小调整。
///
/// v0.4.3：错误处理升级
/// - 顶部叠加 ErrorBannerList 显示所有活动错误
/// - 错误按严重度排序（error > warning > info）
/// - 详情面板可查看完整 stderr（之前的 3 行截断已解除）
/// - 错误自动消失或 sticky
struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @ObservedObject private var errorCenter = ErrorCenter.shared

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                // v0.4.3：错误横幅列表（替代旧的单条错误横幅）
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

/// 左侧转换面板。
struct ConversionPanelView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(viewModel.selectedType.displayName)
                    .font(.title2.bold())

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
                    FileListView(urls: viewModel.inputURLs)
                }

                ConversionOptionsView()

                HStack {
                    Button("选择输出文件夹") { viewModel.pickOutputDirectory() }
                    if let dir = viewModel.outputDirectory {
                        Text(dir.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
    }
}

/// 文件列表视图。
struct FileListView: View {
    let urls: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已选文件")
                .font(.headline)
            ForEach(urls, id: \.path) { url in
                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

/// Office 安装指引 Sheet（当用户点击 Office 转换但未安装任何后端时显示）。
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
                    icon: "checkmark.seal.fill",
                    iconColor: .green,
                    title: "Microsoft Office 365",
                    subtitle: "原生导出，质量最高",
                    detail: "如果已安装 Microsoft Word/Excel/PowerPoint，\n应用会自动调用它们，无需额外操作。"
                )
                OptionRow(
                    icon: "doc.text.fill",
                    iconColor: .blue,
                    title: "Apple iWork（Pages/Numbers/Keynote）",
                    subtitle: "系统自带，免费",
                    detail: "如果已安装 iWork 套件，应用会自动调用它们。"
                )
                OptionRow(
                    icon: "arrow.down.circle.fill",
                    iconColor: .orange,
                    title: "LibreOffice",
                    subtitle: "免费开源，约 300MB",
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
                if let action = action {
                    action()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
    }
}