import SwiftUI
import PDFConverterCore

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("离线工具链") {
                Text("应用从 `Contents/Resources/tools` 加载 CLI，也可回退到系统 PATH（Homebrew 等）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(viewModel.toolReport.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Image(systemName: item.available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.available ? .green : .red)
                        VStack(alignment: .leading) {
                            Text(item.tool.name)
                            if let path = item.path {
                                Text(path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Section("分发") {
                LabeledContent("渠道", value: "直接分发（非 Mac App Store）")
                LabeledContent("沙盒", value: "已关闭，可调用捆绑 CLI")
            }

            Section("关于") {
                LabeledContent("版本", value: PDFConverterCore.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
    }
}
