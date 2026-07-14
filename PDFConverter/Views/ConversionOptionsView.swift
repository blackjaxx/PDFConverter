import SwiftUI
import PDFConverterCore

/// 根据当前选中的转换类型**动态显示**不同的参数选项。
///
/// 核心设计：使用 `switch viewModel.selectedType.category` 按分类分发 UI，
/// 同一分类下的具体类型（如 PNG、JPEG、TIFF）共享相同的参数界面。
/// 每个分支直接读写 `viewModel.parameters` 中的对应属性，
/// 通过 SwiftUI 的双向绑定实现即时更新。
struct ConversionOptionsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        GroupBox("参数") {
            VStack(alignment: .leading, spacing: 12) {
                switch viewModel.selectedType.category {
                // PDF 转图片：使用 Stepper 控制 DPI（分辨率），范围 72~600
                case .pdfToImage:
                    Stepper("DPI: \(viewModel.parameters.dpi)", value: $viewModel.parameters.dpi, in: 72...600, step: 25)
                // 图片转 PDF、合并、拆分：无需额外参数
                case .imageToPDF, .merge, .split:
                    EmptyView()
                // PDF 转文本：目前仅提示，页范围选择后续版本实现
                case .pdfToText:
                    Text("可选页范围在后续版本提供")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                // Office 文档与 PDF 互转：使用智能降级引擎
                // 优先级：Microsoft Office → Apple iWork → LibreOffice (headless)
                case .officeToPDF, .pdfToOffice:
                    if viewModel.isBackendAvailable(for: viewModel.selectedType) {
                        Text("智能降级：Microsoft Office → Apple iWork → LibreOffice")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        // 后端全部不可用，显示安装指引
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
                // 压缩：提供 Ghostscript 的四种预设档位
                case .compress:
                    Picker("压缩档位", selection: $viewModel.parameters.compressionLevel) {
                        Text("屏幕 /screen").tag("screen")
                        Text("电子书 /ebook").tag("ebook")
                        Text("打印 /printer").tag("printer")
                        Text("印前 /prepress").tag("prepress")
                    }
                // 旋转：三个固定角度选项
                case .rotate:
                    Picker("旋转角度", selection: $viewModel.parameters.rotationDegrees) {
                        Text("90°").tag(90)
                        Text("180°").tag(180)
                        Text("270°").tag(270)
                    }
                // 水印：自由文本输入，空字符串视为无
                case .watermark:
                    TextField("水印文字", text: Binding(
                        get: { viewModel.parameters.watermarkText ?? "" },
                        set: { viewModel.parameters.watermarkText = $0.isEmpty ? nil : $0 }
                    ))
                // 加密/解密：使用 SecureField 隐藏密码输入
                case .encrypt, .decrypt:
                    SecureField("密码", text: Binding(
                        get: { viewModel.parameters.password ?? "" },
                        set: { viewModel.parameters.password = $0.isEmpty ? nil : $0 }
                    ))
                // OCR：输入 Tesseract 语言代码，用 + 分隔多语言，如 "chi_sim+eng"
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
                // HTML 转 PDF：仅提示，无额外参数（由 WKWebView 引擎处理）
                case .htmlToPDF:
                    Text("支持本地 HTML 文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                // AI 处理：翻译语言选择、字符上限、附加指令
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