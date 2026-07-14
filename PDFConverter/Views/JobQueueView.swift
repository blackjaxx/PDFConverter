import SwiftUI
import PDFConverterCore

/// v0.4.4：任务队列添加批量操作
/// - 顶部右上角添加菜单按钮（清空已完成 / 清空全部）
/// - 每个失败任务可点击展开 + 重试 + 查看完整错误
struct JobQueueView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("任务队列")
                    .font(.headline)
                Spacer()

                // 批量操作菜单
                Menu {
                    Button("清空已完成") {
                        Task { await viewModel.clearCompletedJobs() }
                    }
                    .disabled(!hasCompletedJobs)

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

    /// 是否有已完成/失败/取消的任务
    private var hasCompletedJobs: Bool {
        viewModel.jobs.contains { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }
}

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
                // 添加单条删除按钮（已完成的任务可删除）
                if job.status == .completed || job.status == .failed || job.status == .cancelled {
                    Button {
                        Task {
                            await viewModel.removeJob(id: job.id)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("从列表移除（不影响磁盘文件）")
                }
            }

            if job.status == .running || job.status == .completed {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(progressColor)
            }

            if job.status == .failed, let error = job.errorMessage {
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
                    HStack {
                        Button {
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