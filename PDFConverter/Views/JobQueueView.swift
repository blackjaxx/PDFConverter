import SwiftUI
import PDFConverterCore

/// v0.4.9 重构 - 修复之前的几个问题：
/// - 空状态不再用 `.frame(maxHeight: .infinity)` 在容器里顶出范围
/// - 任务列表有合理 padding
/// - 顶部按钮间距与设计一致
struct JobQueueView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if viewModel.jobs.isEmpty {
                emptyState
            } else {
                jobList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("任务队列")
                .font(.headline)
            if !viewModel.jobs.isEmpty {
                Text("\(viewModel.jobs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.background.tertiary))
            }
            Spacer()
            Menu {
                Button("清空已完成") {
                    Task { await viewModel.clearCompletedJobs() }
                }
                .disabled(!viewModel.hasJobsInState(.completed, .failed, .cancelled))

                Button("清空全部（含运行中）", role: .destructive) {
                    Task { await viewModel.clearAllJobs() }
                }
                .disabled(viewModel.jobs.isEmpty)

                Divider()

                Button("刷新") {
                    Task { await viewModel.refreshJobs() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
            .help("批量操作")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无任务")
                .font(.headline)
            Text("添加文件并点击工具栏的\"开始转换\"")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var jobList: some View {
        List(viewModel.jobs) { job in
            JobRowView(job: job)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
        .listStyle(.inset)
    }
}

struct JobRowView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let job: ConversionJob
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(job.type.displayName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                StatusBadge(status: job.status)
                // 单条删除（仅对已完成/失败/取消的任务可移除）
                if job.status.needsTerminalState {
                    Button {
                        Task { await viewModel.removeJob(id: job.id) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("从列表移除（不影响磁盘文件）")
                }
            }

            // 进度条（仅 running/completed 显示）
            if job.status.needsProgressBar {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(progressColor)
            }

            // 失败错误展示
            if job.status == .failed, let error = job.errorMessage {
                failureSection(error: error)
            }

            // 输出文件链接
            if !job.outputURLs.isEmpty {
                ForEach(job.outputURLs, id: \.path) { url in
                    HStack {
                        Button(url.lastPathComponent) {
                            viewModel.revealInFinder(url)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                        .lineLimit(1)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func failureSection(error: String) -> some View {
        let details = job.stderrDetails ?? error
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(isExpanded ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(spacing: 8) {
                    Button {
                        viewModel.showJobError(job)
                    } label: {
                        Label("查看完整错误", systemImage: "info.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        viewModel.retryJob(job)
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var progressColor: Color {
        switch job.status {
        case .completed: return .green
        case .failed: return .red
        default: return .accentColor
        }
    }
}

/// v0.4.9：状态徽章 - 用 enum 的 computed property 替代 switch 嵌套
struct StatusBadge: View {
    let status: JobStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(status.color.opacity(0.15)))
            .foregroundStyle(status.color)
    }
}

extension JobStatus {
    /// 显示标签
    var label: String {
        switch self {
        case .pending: "等待"
        case .running: "进行中"
        case .completed: "完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }

    /// 显示颜色
    var color: Color {
        switch self {
        case .pending: .secondary
        case .running: .blue
        case .completed: .green
        case .failed: .red
        case .cancelled: .orange
        }
    }

    /// 是否属于「终态」（可以删除的任务状态）
    var needsTerminalState: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        case .pending, .running: false
        }
    }

    /// 是否需要展示进度条（running 和 completed 展示，其他不展示）
    var needsProgressBar: Bool {
        switch self {
        case .running, .completed: true
        case .pending, .failed, .cancelled: false
        }
    }
}