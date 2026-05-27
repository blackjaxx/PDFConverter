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
        category.displayName
    }
}
