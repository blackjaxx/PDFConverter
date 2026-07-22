import SwiftUI
import PDFConverterCore

/// 参数选项视图 - 根据 `selectedType` 动态显示不同参数
///
/// v0.4.9 改进：
/// - 用 `.controlSize(.regular)` 统一控件大小
/// - 标签自适应宽度，长参数不截断
/// - 简化压缩档位选择（去掉 /screen 等冗余后缀）
struct ConversionOptionsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let onReset: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                header

                switch viewModel.selectedType.category {
                case .pdfToImage:
                    parameterRow(label: "DPI") {
                        Text("\(Int(viewModel.parameters.dpi))")
                            .font(.body.monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                        Stepper("", value: $viewModel.parameters.dpi, in: 72...600, step: 25)
                            .labelsHidden()
                    }

                case .imageToPDF, .merge, .split:
                    Text("此类型无需额外参数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)

                case .pdfToText:
                    Text("可选页范围在后续版本提供")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)

                case .officeToPDF, .pdfToOffice:
                    if viewModel.isBackendAvailable(for: viewModel.selectedType) {
                        Label("智能降级：MS Office → iWork → LibreOffice",
                              systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        officeInstallHint
                    }

                case .compress:
                    parameterRow(label: "压缩档位") {
                        Picker("", selection: $viewModel.parameters.compressionLevel) {
                            Text("屏幕").tag("screen")
                            Text("电子书").tag("ebook")
                            Text("打印").tag("printer")
                            Text("印前").tag("prepress")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 160)
                    }

                case .rotate:
                    parameterRow(label: "旋转角度") {
                        Picker("", selection: $viewModel.parameters.rotationDegrees) {
                            Text("90°").tag(90)
                            Text("180°").tag(180)
                            Text("270°").tag(270)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                    }

                case .watermark:
                    parameterRow(label: "水印文字") {
                        TextField("", text: Binding(
                            get: { viewModel.parameters.watermarkText ?? "" },
                            set: { viewModel.parameters.watermarkText = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    }

                case .encrypt, .decrypt:
                    parameterRow(label: "密码") {
                        SecureField("", text: Binding(
                            get: { viewModel.parameters.password ?? "" },
                            set: { viewModel.parameters.password = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    }

                case .ocr:
                    parameterRow(label: "OCR 语言") {
                        TextField("chi_sim+eng", text: Binding(
                            get: { viewModel.parameters.ocrLanguages.joined(separator: "+") },
                            set: {
                                viewModel.parameters.ocrLanguages = $0
                                    .split(separator: "+")
                                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                    }

                case .htmlToPDF:
                    Text("支持本地 HTML 文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)

                case .ai:
                    VStack(alignment: .leading, spacing: 8) {
                        parameterRow(label: "翻译语言") {
                            Picker("", selection: $viewModel.parameters.aiTargetLanguage) {
                                Text("简体中文").tag("简体中文")
                                Text("English").tag("English")
                                Text("日本語").tag("日本語")
                            }
                            .labelsHidden()
                            .disabled(viewModel.selectedType != .pdfAITranslate)
                            .frame(maxWidth: 160)
                        }
                        parameterRow(label: "字符上限") {
                            Text("\(viewModel.parameters.aiMaxInputChars)")
                                .font(.body.monospacedDigit())
                                .frame(width: 60, alignment: .trailing)
                            Stepper("", value: $viewModel.parameters.aiMaxInputChars, in: 2000...50000, step: 1000)
                                .labelsHidden()
                        }
                        parameterRow(label: "附加指令") {
                            TextField("", text: Binding(
                                get: { viewModel.parameters.aiCustomInstruction ?? "" },
                                set: { viewModel.parameters.aiCustomInstruction = $0.isEmpty ? nil : $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        }
                        Text("需联网；正文经 pdftotext 提取后发送至 DeepSeek。请勿上传敏感文档。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private var header: some View {
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
    }

    @ViewBuilder
    private var officeInstallHint: some View {
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
                Text("• LibreOffice：brew install --cask libreoffice")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    /// v0.4.9: 参数行 - 标签自适应宽度（不固定 frame）
    @ViewBuilder
    private func parameterRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}