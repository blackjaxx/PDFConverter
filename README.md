# PDF Converter (macOS)

原生 macOS SwiftUI PDF 转换器，支持 **PDF ⇄ 图片 / 文本 / Office / HTML / OCR / AI** 等可扩展转换类型。**非 Mac App Store** 分发，离线运行，零网络依赖（AI 功能除外）。

## 项目目标

这是一个面向**学习与二次开发**的开源项目，设计清晰、注释详细，适合 Swift/SwiftUI 初学者阅读和理解 macOS 应用的完整架构。

## 下载与安装

### 从 GitHub Releases 下载（推荐）

前往 [Releases](https://github.com/KleinYuan/PDFConverter/releases) 页面，下载最新的 `.dmg` 文件：

1. 双击打开 `.dmg` 文件
2. 将 `PDFConverter.app` 拖入 `Applications` 文件夹
3. 首次运行时，右键点击应用 → 选择「打开」（macOS Gatekeeper 限制）

>  每次推送 `v*` 标签（如 `v0.2.0`）时，GitHub Actions 会自动构建并上传 DMG 包。

### 本地构建

```bash
# 1. 安装开发依赖（可选，用于本地调试）
brew install poppler qpdf ghostscript tesseract libreoffice

# 2. 打开项目
open PDFConverter.xcodeproj
# Xcode → Product → Run (Cmd+R)

# 3. 运行 Core 包单元测试
cd Packages/PDFConverterCore && swift test

# 4. 打包 DMG（本地）
./Scripts/package-dmg.sh
```

## 功能矩阵

| 分类 | 支持的类型 | 使用的引擎 |
|------|-----------|-----------|
| PDF → 图片 | PNG / JPEG / TIFF | Poppler（pdftoppm） |
| 图片 → PDF | PNG / JPEG → PDF | PDFKit（系统原生） |
| PDF → 文本 | 纯文本提取 | Poppler（pdftotext） |
| Office → PDF | Word / Excel / PPT | LibreOffice（headless） |
| PDF → Office | Word / Excel | LibreOffice（headless） |
| HTML → PDF | 网页转 PDF | WebKit（WKWebView） |
| 页面操作 | 合并 / 拆分 / 旋转 | PDFKit + qpdf |
| 优化 | PDF 压缩 | Ghostscript |
| 编辑 | 添加水印 | PDFKit |
| 安全 | 加密 / 解密 | qpdf（256-bit AES） |
| OCR | 可搜索 PDF | Tesseract |
| AI | 摘要 / 翻译 / Markdown | DeepSeek Chat API |

## 项目架构

```
┌──────────────────────────────────────────────────┐
│   PDFConverter（SwiftUI App 层）                   │
│   ├── App/PDFConverterApp.swift    → 应用入口       │
│   ├── Views/                      → UI 视图        │
│   ├── ViewModels/AppViewModel.swift → 核心 ViewModel │
│   ├── Services/AppWebKitEngine.swift → HTML→PDF    │
│   └── Services/AI/                → DeepSeek 集成   │
└────────────────────┬─────────────────────────────┘
                     │ import PDFConverterCore
┌────────────────────▼─────────────────────────────┐
│   PDFConverterCore（Swift Package 核心层）          │
│   ├── Protocols/ConversionEngine.swift → 引擎协议  │
│   ├── Models/      → 数据模型（类型/任务/参数）      │
│   ├── Services/    → 注册表/编排器/工具定位/进程执行  │
│   └── Engines/     → 各 CLI 引擎实现               │
└────────────────────┬─────────────────────────────┘
                     │ Process / PDFKit
┌────────────────────▼─────────────────────────────┐
│   系统工具层                                       │
│   PDFKit（macOS 原生）+ CLI 工具（Poppler 等）       │
└──────────────────────────────────────────────────┘
```

## 核心设计思想

### 1. 可插拔引擎（ConversionEngine 协议）

项目的核心抽象是 `ConversionEngine` 协议。每种转换功能都由一个独立的引擎实现，只需实现三个要素：

```swift
protocol ConversionEngine {
    var kind: EngineKind { get }                          // 引擎标识
    func supportedTypes() -> Set<ConversionType>          // 支持的转换类型
    func convert(context: ConversionContext) async throws // 执行转换
}
```

**优势**：新增一种转换功能时，只需编写一个新的 Engine 并注册到 `EngineRegistry`，无需修改现有代码。

### 2. 依赖注入（EngineRegistry）

`EngineRegistry` 持有所有引擎实例，维护 `ConversionType → Engine` 的映射。支持通过构造函数注入自定义引擎列表：

- Core 包默认注册**纯本地引擎**（PDFKit、Poppler、qpdf 等）
- App 层通过 `ViewModel.makeDefaultRegistry()` 补充 **App 层引擎**（WebKit、DeepSeek）

### 3. Actor 任务编排（JobOrchestrator）

`JobOrchestrator` 是一个 Swift `actor`，保证任务队列的线程安全：

1. UI 通过 `enqueue()` 提交 `ConversionJob`
2. Actor 内部调用 `pump()` 递归调度，最多 2 个并发任务
3. 为每个任务创建独立的临时工作目录，执行完成后自动清理
4. 通过 `progressHandler` 回调通知 UI 状态更新

### 4. 三级工具查找（ToolLocator）

`ToolLocator` 按优先级查找 CLI 工具：**缓存 → App Bundle 内置 → 系统 PATH**。用 `OSAllocatedUnfairLock` 保证线程安全，首次查找后缓存结果。

### 5. 异步进程安全（ProcessRunner）

`ProcessRunner` 使用 `readabilityHandler` 实时读取子进程的 stdout/stderr 管道数据，防止大型输出（>64KB）时管道缓冲区溢出导致进程死锁。

## 代码导航（初学者指南）

阅读本项目代码时，建议按以下顺序：

| 步骤 | 文件 | 学习目标 |
|------|------|---------|
| 1 | `Packages/PDFConverterCore/.../ConversionType.swift` | 理解转换类型与分类的枚举设计 |
| 2 | `Packages/PDFConverterCore/.../ConversionEngine.swift` | 理解核心协议：Context、Result、Error |
| 3 | `Packages/PDFConverterCore/.../EngineRegistry.swift` | 理解依赖注入与引擎注册 |
| 4 | `Packages/PDFConverterCore/.../JobOrchestrator.swift` | 理解 Actor 任务调度模式 |
| 5 | 任选一个 Engine（如 `PDFKitEngine.swift`） | 理解引擎的具体实现 |
| 6 | `PDFConverter/ViewModels/AppViewModel.swift` | 理解 MVVM 模式与 UI 状态管理 |
| 7 | `PDFConverter/Views/ContentView.swift` | 理解 SwiftUI 导航布局 |
| 8 | `PDFConverter/Services/AI/AppLLMEngine.swift` | 理解 AI 集成流程（文本提取→API→输出） |

所有源代码均包含详细的中文注释，请直接阅读源码学习。

## AI 功能（DeepSeek）

AI 功能使用 DeepSeek Chat API（兼容 OpenAI 格式），处理流程：

```
PDF 文件 → pdftotext 提取正文 → 字符截断 → DeepSeek API → 输出 .md 文件
```

**注意**：不上传原始 PDF，仅发送提取的纯文本（可在参数中限制字符数）。API Key 存储在系统钥匙串（Keychain）中。

## 增加新转换类型

在 `ConversionType` 增加 case → 实现新的 `ConversionEngine` → 在 `EngineRegistry` 注册即可。

## 分发

### 自动构建（GitHub Actions）

推送 `v*` 格式的 Git 标签即可触发自动构建：

```bash
git tag v0.2.0
git push origin v0.2.0
```

构建流程：安装依赖 → 打包 CLI 工具 → `xcodebuild archive` → 生成 `.dmg` → 上传到 Release。

工作流定义在 [.github/workflows/release.yml](.github/workflows/release.yml)。

### 本地打包

```bash
./Scripts/package-dmg.sh
```

如需分发经过公证的版本，请自行配置 Apple Developer 签名证书与 Notary Tool。

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 模块划分与数据流

## 许可证

本项目采用 [MIT License](LICENSE) 发布，供学习、研究与二次开发使用。

捆绑的 Poppler、qpdf、Ghostscript、LibreOffice、Tesseract 等第三方工具请遵循其各自的开源协议。