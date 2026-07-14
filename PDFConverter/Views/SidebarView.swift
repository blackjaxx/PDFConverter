import SwiftUI
import PDFConverterCore

/// 侧边栏，按 `ConversionCategory` 分类显示所有转换类型，支持单选。
///
/// 数据来源：`viewModel.groupedTypes` 是计算属性，
/// 将 `ConversionType.allCases` 按 `category` 分组，过滤掉空分组。
/// 例如：
/// - "PDF → Image" 分组下有 PNG、JPEG、TIFF
/// - "编辑" 分组下有压缩、旋转、水印、加密/解密
///
/// 使用 `.listStyle(.sidebar)` 获得 macOS 原生侧边栏外观。
///
/// ## 后端可用性徽章
/// 当某个分类的所有后端都不可用时（例如没有任何 Office 软件安装），
/// 该分类下的每个条目都会显示「需安装」红色徽章，让用户知道功能存在
/// 但需要安装额外软件才能使用。
struct SidebarView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        /// `List(selection:)` 通过绑定 `$viewModel.selectedType` 实现**双向同步**：
        /// - 用户点击某个类型时，`selectedType` 自动更新
        /// - ViewModel 其他地方修改 `selectedType` 时，侧边栏高亮也会跟随
        List(selection: $viewModel.selectedType) {
            ForEach(viewModel.groupedTypes, id: \.0) { category, types in
                Section(sectionTitle(category)) {
                    ForEach(types) { type in
                        HStack {
                            Text(type.displayName)
                            Spacer()
                            // 非 MVP 功能标记"预览"标签，提示用户该功能尚在开发中
                            if !type.isAvailableInMVP {
                                Text("预览")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                                    .foregroundStyle(.orange)
                            }
                            // 后端不可用时显示"需安装"红色徽章
                            else if !viewModel.isBackendAvailable(for: type) {
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
    }

    /// 使用 `ConversionCategory.displayName` 获取分类的中文标题。
    /// 例如 `.pdfToImage` → "PDF → 图片"。
    private func sectionTitle(_ category: ConversionCategory) -> String {
        category.displayName
    }
}
