import SwiftUI
import PDFConverterCore

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            HStack(spacing: 0) {
                ConversionPanelView()
                    .frame(minWidth: 380)
                Divider()
                JobQueueView()
                    .frame(minWidth: 320)
            }
        }
        .navigationTitle("PDF Converter")
    }
}

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
