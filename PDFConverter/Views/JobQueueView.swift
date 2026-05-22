import SwiftUI
import PDFConverterCore

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
            if job.status == .running {
                ProgressView(value: job.progress)
            }
            if let error = job.errorMessage {
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
