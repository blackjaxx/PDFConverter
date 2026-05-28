import SwiftUI
import PDFConverterCore

/// 应用的主界面，使用 `NavigationSplitView` 实现三栏布局：
/// - **左侧边栏**：显示按分类分组的转换类型列表
/// - **中间转换面板**：文件选择、参数设置、开始转换按钮
/// - **右侧任务队列**：显示所有转换任务的状态和结果
///
/// `NavigationSplitView` 是 macOS 上最经典的布局模式（类似 Finder），
/// 自动支持侧边栏收折和窗口大小调整。
struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                // 错误横幅：当 viewModel.errorMessage 不为 nil 时显示红色横幅，
                // 点击右侧 X 按钮可关闭（调用 viewModel.clearError()）。
                if let error = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.white)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            viewModel.clearError()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(Color.red)
                }

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
    }
}

/// 左侧转换面板：包含文件拖拽区、文件列表、参数设置和「开始转换」按钮。
/// 所有可变数据通过 `@EnvironmentObject` 从 `AppViewModel` 获取。
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

/// 显示已选择文件的列表，每个文件显示其 `lastPathComponent`（文件名+扩展名）。
/// 放在拖拽区下方，给用户确认已选文件的视觉反馈。
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