import SwiftUI
import PDFConverterCore

/// 偏好设置窗口（macOS 的 `Cmd+,` 菜单），包含：
/// 1. **DeepSeek AI 配置**：API Key、BaseURL、模型名称
/// 2. **离线工具链状态**：显示各 CLI 工具的可用性
/// 3. **分发信息**：渠道和沙盒状态
/// 4. **关于**：版本信息
///
/// 使用 `Form` + `.formStyle(.grouped)` 获得 macOS 原生设置面板外观。
struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            // DeepSeek 配置区域：
            // - API Key 保存在系统 Keychain 中（最安全的方式）
            // - BaseURL 和模型名保存在 UserDefaults 中
            // - SecureField 用于隐藏 API Key 输入
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

            // 离线工具链区域（用 header: 显式形式避免 Xcode 15 下误识别为 TableSection）
            Section {
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

                if !viewModel.isOfficeAutomationAvailable {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Office 转换后端均不可用")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("未检测到 Microsoft Office、Apple iWork 或 LibreOffice。\n请安装任一 Office 套件以启用 Office 文档转换。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("离线工具链")
            }

            // 分发信息：说明应用通过直接分发（非 Mac App Store）和沙盒已关闭，
            // 这意味着应用可以调用 Bundle 内的 CLI 工具，不受沙盒限制。
            Section {
                LabeledContent("渠道", value: "直接分发（非 Mac App Store）")
                LabeledContent("沙盒", value: "已关闭，可调用捆绑 CLI")
            } header: {
                Text("分发")
            }

            Section {
                LabeledContent("版本", value: PDFConverterCore.version)
            } header: {
                Text("关于")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
    }
}
