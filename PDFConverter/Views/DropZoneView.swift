import SwiftUI
import UniformTypeIdentifiers

/// DropZoneView - 拖拽文件区域。
///
/// v0.4.9 改进：
/// - 高度从 160 减到 120，更紧凑
/// - 用 `.background.secondary` 而不是固定颜色，自动适配 dark mode
/// - 用 `.controlBackgroundColor` 替代 `.secondary`，视觉更柔和
struct DropZoneView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )

            HStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isTargeted ? "松手即可添加" : "拖拽文件到此处")
                        .font(.headline)
                    Button("或点击选择文件") { viewModel.pickFiles() }
                        .buttonStyle(.link)
                }
            }
            .padding(20)
        }
        .frame(height: 120)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// 多线程安全：使用 NSLock 保护 urls 数组，避免并发 append 丢数据。
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                guard error == nil else { return }
                let url: URL? = {
                    if let direct = item as? URL { return direct }
                    if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
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