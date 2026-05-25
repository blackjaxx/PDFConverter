import SwiftUI
import PDFConverterCore

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section {
                Link("获取 API Key", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                TextField("API Base URL", text: $viewModel.deepSeekBaseURL)
                TextField("模型", text: $viewModel.deepSeekModel)
                    .help("默认 deepseek-chat")
                SecureField(
                    viewModel.isDeepSeekConfigured ? "API Key（已保存，输入新 Key 可覆盖）" : "API Key",
                    text: $viewModel.deepSeekAPIKeyInput
                )
                HStack {
                    Button("保存") { viewModel.saveDeepSeekSettings() }
                    Button("清除 Key", role: .destructive) { viewModel.clearDeepSeekAPIKey() }
                }
                HStack {
                    Image(systemName: viewModel.isDeepSeekConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(viewModel.isDeepSeekConfigured ? .green : .secondary)
                    Text(viewModel.isDeepSeekConfigured ? "DeepSeek 已配置" : "未配置")
                        .font(.caption)
                }
                Text("仅在你执行 AI 转换时联网；Key 保存在系统钥匙串。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("DeepSeek（云端 AI）")
            }

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
        .frame(width: 520, height: 520)
    }
}
