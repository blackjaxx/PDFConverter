import SwiftUI
import PDFConverterCore

struct ConversionOptionsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        GroupBox("参数") {
            VStack(alignment: .leading, spacing: 12) {
                switch viewModel.selectedType.category {
                case .pdfToImage:
                    Stepper("DPI: \(viewModel.parameters.dpi)", value: $viewModel.parameters.dpi, in: 72...600, step: 25)
                case .imageToPDF, .merge, .split:
                    EmptyView()
                case .pdfToText:
                    Text("可选页范围在后续版本提供")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .officeToPDF, .pdfToOffice:
                    Text("使用内置 LibreOffice（headless）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .compress:
                    Picker("压缩档位", selection: $viewModel.parameters.compressionLevel) {
                        Text("屏幕 /screen").tag("screen")
                        Text("电子书 /ebook").tag("ebook")
                        Text("打印 /printer").tag("printer")
                        Text("印前 /prepress").tag("prepress")
                    }
                case .rotate:
                    Picker("旋转角度", selection: $viewModel.parameters.rotationDegrees) {
                        Text("90°").tag(90)
                        Text("180°").tag(180)
                        Text("270°").tag(270)
                    }
                case .watermark:
                    TextField("水印文字", text: Binding(
                        get: { viewModel.parameters.watermarkText ?? "" },
                        set: { viewModel.parameters.watermarkText = $0.isEmpty ? nil : $0 }
                    ))
                case .encrypt, .decrypt:
                    SecureField("密码", text: Binding(
                        get: { viewModel.parameters.password ?? "" },
                        set: { viewModel.parameters.password = $0.isEmpty ? nil : $0 }
                    ))
                case .ocr:
                    TextField("OCR 语言（如 chi_sim+eng）", text: Binding(
                        get: { viewModel.parameters.ocrLanguages.joined(separator: "+") },
                        set: {
                            viewModel.parameters.ocrLanguages = $0
                                .split(separator: "+")
                                .map { String($0).trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                    ))
                case .htmlToPDF:
                    Text("支持本地 HTML 文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .ai:
                    Picker("翻译目标语言", selection: $viewModel.parameters.aiTargetLanguage) {
                        Text("简体中文").tag("简体中文")
                        Text("English").tag("English")
                        Text("日本語").tag("日本語")
                    }
                    .disabled(viewModel.selectedType != .pdfAITranslate)
                    Stepper(
                        "提取字符上限: \(viewModel.parameters.aiMaxInputChars)",
                        value: $viewModel.parameters.aiMaxInputChars,
                        in: 2000...50000,
                        step: 1000
                    )
                    TextField("附加指令（可选）", text: Binding(
                        get: { viewModel.parameters.aiCustomInstruction ?? "" },
                        set: { viewModel.parameters.aiCustomInstruction = $0.isEmpty ? nil : $0 }
                    ))
                    Text("需联网；正文经 pdftotext 提取后发送至 DeepSeek。请勿上传敏感文档。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
