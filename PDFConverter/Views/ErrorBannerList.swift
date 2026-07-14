import SwiftUI

/// 错误横幅列表 - 在 ContentView 顶部叠加显示所有活动错误。
///
/// 显示规则：
/// - 多个错误垂直堆叠，最多显示 5 个
/// - 自动按 severity 排序（error > warning > info）
/// - 自动消失的（非 sticky）错误显示倒计时进度条
/// - 点击「详情」按钮可查看完整 stderr 等
/// - 点击「关闭」移除该错误
struct ErrorBannerList: View {
    @ObservedObject var center: ErrorCenter

    var body: some View {
        VStack(spacing: 4) {
            // 按严重度排序：error > warning > info
            ForEach(sortedErrors) { error in
                ErrorBanner(error: error)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: sortedErrors)
        .sheet(item: $center.detailError) { error in
            ErrorDetailSheet(error: error)
        }
    }

    private var sortedErrors: [AppError] {
        center.errors.sorted { lhs, rhs in
            // error > warning > info
            let order: [AppErrorSeverity: Int] = [.error: 0, .warning: 1, .info: 2]
            return (order[lhs.severity] ?? 3) < (order[rhs.severity] ?? 3)
        }
    }
}

/// 单个错误横幅。
struct ErrorBanner: View {
    let error: AppError
    @ObservedObject private var center = ErrorCenter.shared
    @State private var showDetail = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: error.severity.icon)
                .font(.title3)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(error.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    if let details = error.details, !details.isEmpty {
                        Button {
                            center.showDetail(error)
                        } label: {
                            Label("详情", systemImage: "info.circle")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .buttonStyle(.borderless)
                        .help("查看完整错误信息")
                    }
                    Button {
                        center.remove(id: error.id)
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.borderless)
                    .help("关闭")
                }
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)

                if !error.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(error.actions) { action in
                            Button {
                                Task { await action.callback() }
                            } label: {
                                Text(action.label)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(actionButtonColor(action.role))
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [error.severity.color.opacity(0.95), error.severity.color],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: error.severity.color.opacity(0.3), radius: 4, y: 2)
        .padding(.horizontal, 8)
    }

    private func actionButtonColor(_ role: AppErrorAction.ActionRole) -> Color {
        switch role {
        case .primary: return .white.opacity(0.95)
        case .secondary: return .white.opacity(0.25)
        case .cancel: return .clear
        }
    }
}

/// 错误详情 Sheet - 显示完整的 stderr 等技术信息。
struct ErrorDetailSheet: View {
    let error: AppError
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: error.severity.icon)
                    .foregroundStyle(error.severity.color)
                Text(error.title)
                    .font(.title3.bold())
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("错误描述")
                    .font(.headline)
                Text(error.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let details = error.details, !details.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("详细信息")
                        .font(.headline)
                    ScrollView {
                        Text(details)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .frame(maxHeight: 300)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(details, forType: .string)
                    } label: {
                        Label("复制到剪贴板", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("时间: \(error.timestamp.formatted(date: .abbreviated, time: .standard))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }
}