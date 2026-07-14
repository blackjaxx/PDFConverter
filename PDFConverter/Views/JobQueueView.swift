import SwiftUI
import PDFConverterCore

/// 任务队列视图。
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

/// 单个任务行。
///
/// v0.4.3 升级：
/// - 失败任务可点击展开查看完整错误（不再限制 3 行）
/// - 状态徽章和进度条颜色区分更清晰
/// - 添加「在 Finder 中显示」快捷按钮
struct JobRowView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let job: ConversionJob
    @State private var isExpanded: Bool = false
    @ObservedObject private var errorCenter = ErrorCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.type.displayName)
                    .font(.subheadline.bold())
                Spacer()
                statusBadge
            }

            if job.status == .running || job.status == .completed {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(progressColor)
            }

            if job.status == .failed, let error = job.errorMessage {
                // v0.4.3：可点击展开错误详情
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
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
                    HStack {
                        Button {
                            // v0.4.3：使用 stderrDetails（完整信息）而非 errorMessage（短描述）
                            let details = job.stderrDetails ?? job.errorMessage ?? "未知错误"
                            errorCenter.showDetail(AppError(
                                severity: .error,
                                title: "\(job.type.displayName) 失败详情",
                                message: job.errorMessage ?? "未知错误",
                                details: details
                            ))
                        } label: {
                            Label("查看完整错误", systemImage: "info.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            // 重试：重新创建一个同类型的 job
                            viewModel.retryJob(job)
                        } label: {
                            Label("重试", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.leading, 18)
                }
            }

            if !job.outputURLs.isEmpty {
                ForEach(job.outputURLs, id: \.path) { url in
                    HStack {
                        Button(url.lastPathComponent) { viewModel.revealInFinder(url) }
                            .buttonStyle(.link)
                            .font(.caption)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var progressColor: Color {
        switch job.status {
        case .completed: return .green
        case .failed: return .red
        default: return .blue
        }
    }

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