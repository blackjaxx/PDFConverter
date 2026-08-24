import SwiftUI
import PDFConverterCore

/// 侧边栏 — 按 `ConversionCategory` 分类显示所有转换类型。
///
/// v0.5.0 修复：
/// - 添加 `.navigationTitle` 给侧边栏列，让系统在标题栏区域预留空间，
///   修复列表内容与窗口红绿灯按钮重叠的问题
struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        List(selection: $viewModel.selectedType) {
            ForEach(viewModel.groupedTypes, id: \.0) { category, types in
                Section {
                    ForEach(types) { type in
                        ConversionTypeRow(
                            type: type,
                            isBackendAvailable: viewModel.isBackendAvailable(for: type)
                        )
                        .tag(type)
                    }
                } header: {
                    Text(category.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        // v0.5.0 关键修复：侧边栏列必须有 navigationTitle，
        // 否则 List 内容会顶到窗口标题栏，与红绿灯按钮重叠
        .navigationTitle("转换类型")
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.selectedType = .pdfToPNG
                } label: {
                    Label("默认", systemImage: "arrow.uturn.left")
                }
                .help("重置为默认类型（PDF → PNG）")
            }
        }
    }
}

/// 单行结构 + 状态徽章
private struct ConversionTypeRow: View {
    let type: ConversionType
    let isBackendAvailable: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(type.displayName)
                .lineLimit(1)
            Spacer(minLength: 4)
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if !type.isAvailableInMVP {
            BadgeLabel(text: "预览", color: .orange)
        } else if !isBackendAvailable {
            BadgeLabel(text: "需安装", color: .red)
        }
    }
}

private struct BadgeLabel: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}