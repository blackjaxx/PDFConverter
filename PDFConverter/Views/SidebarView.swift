import SwiftUI
import PDFConverterCore

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

    private func sectionTitle(_ category: ConversionCategory) -> String {
        switch category {
        case .pdfToImage: return "PDF → 图片"
        case .imageToPDF: return "图片 → PDF"
        case .pdfToText: return "PDF → 文本"
        case .officeToPDF: return "Office → PDF"
        case .pdfToOffice: return "PDF → Office"
        case .htmlToPDF: return "网页"
        case .compress: return "优化"
        case .merge, .split: return "页面"
        case .rotate, .watermark: return "编辑"
        case .encrypt, .decrypt: return "安全"
        case .ocr: return "OCR"
        case .ai: return "AI (DeepSeek)"
        }
    }
}
