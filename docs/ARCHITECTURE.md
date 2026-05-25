# Architecture

## Layering

```
┌─────────────────────────────────────────┐
│  PDFConverter (SwiftUI App)             │
│  - Views / AppViewModel                 │
│  - AppWebKitEngine (WKWebView → PDF)    │
└─────────────────┬───────────────────────┘
                  │ import PDFConverterCore
┌─────────────────▼───────────────────────┐
│  PDFConverterCore (Swift Package)       │
│  ConversionType / ConversionJob         │
│  ConversionEngine protocol              │
│  EngineRegistry → JobOrchestrator       │
│  ToolLocator + ProcessRunner            │
└─────────────────┬───────────────────────┘
                  │ Process / PDFKit
┌─────────────────▼───────────────────────┐
│  Bundled CLI + system PDFKit            │
└─────────────────────────────────────────┘
```

## Extensibility

| Step | Action |
|------|--------|
| 1 | Add `ConversionType` + `ConversionCategory` |
| 2 | Implement `supportedTypes()` + `convert()` on an engine |
| 3 | Register engine in `EngineRegistry` init list (or inject via `EngineRegistry(engines:)`) |
| 4 | Add UI options in `ConversionOptionsView` if needed |

App-only engines (WebKit) live in the app target but conform to `ConversionEngine` in Core.

## Engine map

| Engine | Types |
|--------|-------|
| PDFKit | 图片→PDF, 合并, 旋转, 水印 |
| Poppler | PDF→PNG/JPEG/TIFF, PDF→文本 |
| qpdf | 拆分, 加密, 解密 |
| Ghostscript | 压缩 |
| LibreOffice | Office↔PDF/Word/Excel |
| Tesseract | OCR 可搜索 PDF |
| WebKit (App) | HTML→PDF |
| DeepSeek (App) | AI 摘要 / 翻译 / Markdown |

### AI pipeline

1. `PDFTextExtractor` (Poppler `pdftotext`)
2. `DeepSeekClient` → `POST /v1/chat/completions`
3. Write `.md` output

API Key stored in Keychain; base URL / model in UserDefaults.

## Non–App Store

- `com.apple.security.app-sandbox` = **false**
- Bundled binaries under `Resources/tools`
- Optional `PATH` fallback for development

## Job flow

1. UI builds `ConversionJob`
2. `JobOrchestrator.enqueue` → queue
3. Resolve engine via `EngineRegistry`
4. `ConversionContext` with temp work dir
5. Engine runs CLI or PDFKit
6. Outputs moved to user directory
7. Status pushed to UI via handler
