# PDF Converter (macOS)

原生 SwiftUI 离线 PDF 转换器，**非 Mac App Store** 分发。支持 PDF/图片/Office/OCR 等可扩展转换类型。

## 架构

- **PDFConverter** — SwiftUI 应用（拖拽、任务队列、设置、WebKit HTML→PDF）
- **PDFConverterCore** — Swift Package：模型、`ConversionEngine` 协议、各 CLI 引擎、`JobOrchestrator`

新增转换类型：在 `ConversionType` 增加 case → 实现或扩展对应 `ConversionEngine` → 在 `EngineRegistry` 注册（默认已自动聚合）。

## 环境要求

- macOS 13+
- Xcode 15+
- 开发阶段可用 Homebrew 工具；发布前运行 `Scripts/bundle-tools.sh` 将 CLI 打入 `Resources/tools`

```bash
brew install poppler qpdf ghostscript tesseract libreoffice
```

## 打开与编译

```bash
open PDFConverter.xcodeproj
# Product → Run
```

命令行编译：

```bash
xcodebuild -project PDFConverter.xcodeproj -scheme PDFConverter -configuration Debug build
```

Core 包单测：

```bash
cd Packages/PDFConverterCore && swift test
```

## 离线工具目录

```
PDFConverter.app/Contents/Resources/tools/
├── poppler/
├── qpdf/
├── ghostscript/
├── libreoffice/
└── tesseract/
```

## 分发（.direct）

1. `chmod +x Scripts/bundle-tools.sh && ./Scripts/bundle-tools.sh`
2. Archive → Export → 签名与公证（Notarization）
3. 用 `create-dmg` 或 Disk Utility 制作 `.dmg`

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 模块与数据流

## 许可证

按需自行添加；捆绑的 Poppler/qpdf/Ghostscript/LibreOffice/Tesseract 请遵循各自开源协议。
