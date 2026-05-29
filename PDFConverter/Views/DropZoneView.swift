import SwiftUI
import UniformTypeIdentifiers

/// 拖拽文件区域，支持两种文件选择方式：
/// 1. **拖拽**：从 Finder 拖入文件到虚线圈区域
/// 2. **点击**：点击 "或点击选择文件" 链接按钮，弹出系统文件选择对话框
///
/// 虚线边框的颜色会随拖拽状态变化：未拖拽时为灰色，拖拽悬停时变为高亮色。
struct DropZoneView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    /// 标记是否正在有文件悬停于拖拽区域上方
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("拖拽文件到此处")
                    .font(.headline)
                Button("或点击选择文件") { viewModel.pickFiles() }
                    .buttonStyle(.link)
            }
            .padding(32)
        }
        .frame(height: 160)
        /// `onDrop(of: [.fileURL])` 接受 `.fileURL` 类型的拖拽内容。
        /// `isTargeted` 参数自动跟踪拖拽悬停状态，控制虚线颜色变化。
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// 处理拖拽投放的文件。
    ///
    /// 关键实现细节：
    /// - 使用 `NSItemProvider.loadItem` 异步加载每个被拖拽文件的 URL
    /// - 使用 `DispatchGroup` 等待**所有**文件 URL 加载完成后，
    ///   再统一更新 `viewModel.inputURLs`
    /// - URL 可能以 `URL` 或 `Data` 两种格式提供，这里两种都处理
    ///
    /// 返回值 `true` 表示接受该拖拽操作。
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                if error != nil {
                    return
                }
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { viewModel.inputURLs = urls }
        }
        return true
    }
}