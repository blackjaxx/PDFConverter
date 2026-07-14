import SwiftUI
import PDFConverterCore

/// 根据当前选中的转换类型动态显示不同的参数选项。
///
/// v0.4.4 升级：
/// - 顶部标题右侧添加「重置参数」按钮，恢复当前类型的所有参数为默认值
struct ConversionOptionsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let onReset: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // 标题 + 重置按钮
                HStack {
                    Text("参数")
                        .font(.headline)
                    Spacer()
                    Button {
                        onReset()
                    } label: {
                        Label("重置", systemImage: "arrow.counterclockwise")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("恢复当前类型的所有参数为默认值")
                }

                switch viewModel.selectedType.category {
                case .pdfToImage:
                    parameterRow(label: "DPI: \(viewModel.parameters.dpi)") {
                        Stepper("", value: $viewModel.parameters.dpi, in: 72...600, step: 25)
                            .labelsHidden()
                    }
                case .imageToPDF, .merge, .split:
                    Text("此类型无需额外参数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .pdfToText:
                    Text("可选页范围在后续版本提供")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .officeToPDF, .pdfToOffice:
                    if viewModel.isBackendAvailable(for: viewModel.selectedType) {
                        Text("智能降级：Microsoft Office → Apple iWork → LibreOffice")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("未检测到 Office 转换后端", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            Text("按以下任一方式安装即可启用：")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("• Microsoft Office 365（推荐）")
                                Text("• Apple iWork（Pages/Numbers/Keynote）")
                                Text("• LibreOffice（免费，约 300MB）：brew install --cask libreoffice")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                    }
                case .compress:
                    parameterRow(label: "压缩档位") {
                        Picker("", selection: $viewModel.parameters.compressionLevel) {
                            Text("屏幕 /screen").tag("screen")
                            Text("电子书 /ebook").tag("ebook")
                            Text("打印 /printer").tag("printer")
                            Text("印前 /prepress").tag("prepress")
                        }
                        .labelsHidden()
                    }
                case .rotate:
                    parameterRow(label: "旋转角度") {
                        Picker("", selection: $viewModel.parameters.rotationDegrees) {
                            Text("90°").tag(90)
                            Text("180°").tag(180)
                            Text("270°").tag(270)
                        }
                        .labelsHidden()
                    }
                case .watermark:
                    parameterRow(label: "水印文字") {
                        TextField("", text: Binding(
                            get: { viewModel.parameters.watermarkText ?? "" },
                            set: { viewModel.parameters.watermarkText = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                case .encrypt, .decrypt:
                    parameterRow(label: "密码") {
                        SecureField("", text: Binding(
                            get: { viewModel.parameters.password ?? "" },
                            set: { viewModel.parameters.password = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                case .ocr:
                    parameterRow(label: "OCR 语言（如 chi_sim+eng）") {
                        TextField("", text: Binding(
                            get: { viewModel.parameters.ocrLanguages.joined(separator: "+") },
                            set: {
                                viewModel.parameters.ocrLanguages = $0
                                    .split(separator: "+")
                                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                case .htmlToPDF:
                    Text("支持本地 HTML 文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .ai:
                    VStack(alignment: .leading, spacing: 8) {
                        parameterRow(label: "翻译目标语言") {
                            Picker("", selection: $viewModel.parameters.aiTargetLanguage) {
                                Text("简体中文").tag("简体中文")
                                Text("English").tag("English")
                                Text("日本語").tag("日本語")
                            }
                            .labelsHidden()
                            .disabled(viewModel.selectedType != .pdfAITranslate)
                        }
                        parameterRow(label: "提取字符上限: \(viewModel.parameters.aiMaxInputChars)") {
                            Stepper("", value: $viewModel.parameters.aiMaxInputChars, in: 2000...50000, step: 1000)
                                .labelsHidden()
                        }
                        parameterRow(label: "附加指令（可选）") {
                            TextField("", text: Binding(
                                get: { viewModel.parameters.aiCustomInstruction ?? "" },
                                set: { viewModel.parameters.aiCustomInstruction = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        Text("需联网；正文经 pdftotext 提取后发送至 DeepSeek。请勿上传敏感文档。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 参数行：左侧标签 + 右侧控件，统一对齐。
    @ViewBuilder
    private func parameterRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 180, alignment: .leading)
                .font(.caption)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}