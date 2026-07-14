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
    /// 关键修复：使用 NSLock 保护共享的 urls 数组，避免 `loadItem` 的
    /// 回调在多线程并发 append 导致数据丢失或崩溃。
    ///
    /// 返回值 `true` 表示接受该拖拽操作。
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // 用 NSLock 保护的线程安全数组
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                guard error == nil else { return }
                let url: URL? = {
                    if let direct = item as? URL {
                        return direct
                    } else if let data = item as? Data {
                        return URL(dataRepresentation: data, relativeTo: nil)
                    }
                    return nil
                }()
                guard let url else { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty { viewModel.inputURLs = urls }
        }
        return true
    }
}