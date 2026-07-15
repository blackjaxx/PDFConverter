import SwiftUI

/// 错误横幅列表 - 在 ContentView 顶部叠加显示所有活动错误。
///
/// v0.4.5 增强：
/// - 详情按钮始终显示（即使没有 details），点击会显示"暂无详细信息"+ 调试建议
/// - 详情 Sheet 增加"在 Finder 中显示工作目录"和"查看应用日志"按钮
struct ErrorBannerList: View {
    @ObservedObject var center: ErrorCenter

    var body: some View {
        VStack(spacing: 4) {
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
            let order: [AppErrorSeverity: Int] = [.error: 0, .warning: 1, .info: 2]
            return (order[lhs.severity] ?? 3) < (order[rhs.severity] ?? 3)
        }
    }
}

/// 单个错误横幅。
struct ErrorBanner: View {
    let error: AppError
    @ObservedObject private var center = ErrorCenter.shared

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
                    // v0.4.5：详情按钮始终显示（即使没有 details）
                    Button {
                        center.showDetail(error)
                    } label: {
                        Label("详情", systemImage: "info.circle")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.borderless)
                    .help("查看完整错误信息")
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
                                Task { await action.callback(AppErrorContext.shared) }
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
///
/// v0.4.5 增强：
/// - 始终显示「详细信息」面板（即使 details 为空也提示"未提供详细信息"）
/// - 增加「打开 Console.app」按钮查看系统日志
/// - 增加「复制全部」按钮（标题+消息+详情）
/// - 大文本区域使用等宽字体 + 行号显示
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

            // 错误描述
            VStack(alignment: .leading, spacing: 8) {
                Label("错误描述", systemImage: "text.bubble")
                    .font(.headline)
                Text(error.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            // 详细信息（始终显示）
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("详细信息", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    Spacer()
                    if let details = error.details, !details.isEmpty {
                        Button {
                            copyToClipboard(details)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                                .labelStyle(.titleAndIcon)
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let details = error.details, !details.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(details.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 32, alignment: .trailing)
                                    Text(line.isEmpty ? " " : line)
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 360)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    // 没有 details 时的提示
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                            Text("此错误未提供详细信息")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("可能原因：缺少 CLI 工具、参数无效、用户取消等。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
                }
            }

            // 时间戳 + 调试辅助按钮
            HStack {
                Text("时间: \(error.timestamp.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    openConsoleApp()
                } label: {
                    Label("系统日志", systemImage: "terminal")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("在 Console.app 中查看应用日志")

                Button {
                    copyAllToClipboard()
                } label: {
                    Label("复制全部", systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 640, height: 540)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyAllToClipboard() {
        var parts: [String] = ["[\(error.title)]", error.message]
        if let details = error.details, !details.isEmpty {
            parts.append("---")
            parts.append(details)
        }
        parts.append("---")
        parts.append("时间: \(error.timestamp.formatted(date: .abbreviated, time: .standard))")
        copyToClipboard(parts.joined(separator: "\n"))
    }

    private func openConsoleApp() {
        AppLogger.shared.revealLogFileInFinder()
    }
}