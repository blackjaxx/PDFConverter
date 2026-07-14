import SwiftUI
import PDFConverterCore

/// 任务队列视图，显示所有转换任务的状态。
///
/// 有两种展示模式：
/// 1. **空状态**（`jobs` 为空时）：显示托盘图标和引导文字
/// 2. **任务列表**：每行显示一个 `JobRowView`
///
/// 右上角有刷新按钮（`arrow.clockwise` 图标），手动从 `JobOrchestrator` 拉取最新状态。
struct JobQueueView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("任务队列")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await viewModel.refreshJobs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新任务列表")
            }
            .padding()

            if viewModel.jobs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("暂无任务")
                        .font(.headline)
                    Text("添加文件并点击开始转换")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.jobs) { job in
                    JobRowView(job: job)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// 单个任务行，显示任务的详细信息：
/// - 转换类型名称（如 "PDF → PNG"）
/// - 当前状态徽章（等待/进行中/完成/失败/已取消）
/// - 进度条（running 和 completed 都显示，completed 显示 100%）
/// - 错误信息（红色文字，最多 3 行）
/// - 输出文件链接（点击可在 Finder 中定位）
///
/// v0.4.2 修复：
/// - ProgressView 在 running 和 completed 都显示
/// - 完成时显示淡绿色并显示 100% 进度
struct JobRowView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let job: ConversionJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.type.displayName)
                    .font(.subheadline.bold())
                Spacer()
                statusBadge
            }
            // 修复（v0.4.2）：running 和 completed 都显示进度条
            // - running: 进度随任务实时更新
            // - completed: 显示 100% 作为视觉确认
            // - failed: 显示红色 + 错误信息
            if job.status == .running || job.status == .completed {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(progressColor)
            }
            if let error = job.errorMessage, job.status == .failed {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            if !job.outputURLs.isEmpty {
                ForEach(job.outputURLs, id: \.path) { url in
                    Button(url.lastPathComponent) { viewModel.revealInFinder(url) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// 进度条颜色：完成时绿色，运行时蓝色
    private var progressColor: Color {
        switch job.status {
        case .completed: return .green
        case .failed: return .red
        default: return .blue
        }
    }

    /// 根据任务状态显示不同颜色和文字的徽章。
    @ViewBuilder
    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            switch job.status {
            case .pending: return ("等待", .secondary)
            case .running: return ("进行中", .blue)
            case .completed: return ("完成", .green)
            case .failed: return ("失败", .red)
            case .cancelled: return ("已取消", .orange)
            }
        }()
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}