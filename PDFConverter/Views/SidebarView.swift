import SwiftUI
import PDFConverterCore

/// 侧边栏，按 `ConversionCategory` 分类显示所有转换类型。
///
/// v0.4.4 添加右上角「重置为默认」按钮：快速跳回 `.pdfToPNG`。
struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        List(selection: $viewModel.selectedType) {
            ForEach(viewModel.groupedTypes, id: \.0) { category, types in
                Section(sectionTitle(category)) {
                    ForEach(types) { type in
                        HStack {
                            Text(type.displayName)
                            Spacer()
                            if !type.isAvailableInMVP {
                                Text("预览")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                                    .foregroundStyle(.orange)
                            } else if !viewModel.isBackendAvailable(for: type) {
                                Text("需安装")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.red.opacity(0.15)))
                                    .foregroundStyle(.red)
                            }
                        }
                        .tag(type)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
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

    private func sectionTitle(_ category: ConversionCategory) -> String {
        category.displayName
    }
}
