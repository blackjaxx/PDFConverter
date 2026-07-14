# PDF Converter (macOS)

原生 macOS SwiftUI PDF 转换器，支持 **PDF ⇄ 图片 / 文本 / Office / HTML / OCR / AI** 等可扩展转换类型。**非 Mac App Store** 分发，离线运行，零网络依赖（AI 功能除外）。

## 项目目标

这是一个面向 **学习与二次开发** 的开源项目，设计清晰、注释详细，适合 Swift/SwiftUI 初学者阅读和理解 macOS 应用的完整架构。

![App Icon](docs/app-icon-preview.png)

## 下载与安装

### 从 GitHub Releases 下载（推荐）

前往 [Releases](https://github.com/blackjaxx/PDFConverter/releases) 页面，下载最新的 `.dmg` 文件：

1. 双击打开 `.dmg` 文件
2. 将 `PDFConverter.app` 拖入 `Applications` 文件夹
3. 打开终端，执行 `xattr -cr /Applications/PDFConverter.app`
4. 右键点击应用 → 选择「打开」

> 由于当前 Release 包**未经过 Apple 代码签名与公证**，直接打开会触发 Gatekeeper 拦截。执行上方命令可清除隔离标记后正常运行。

>  每次推送 `v*` 标签（如 `v0.2.6`）时，GitHub Actions 会自动构建并上传 DMG 包。

### 本地构建

```bash
# 1. 安装开发依赖
brew install poppler qpdf ghostscript tesseract
# （可选）Office 文档转换需要 LibreOffice，但 OfficeAutomationEngine
# 会优先尝试系统已有的 Microsoft Office 或 Apple iWork
brew install libreoffice

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
| Office → PDF | Word / Excel / PPT | 智能降级：Microsoft Office → Apple iWork → LibreOffice |
| PDF → Office | Word / Excel | 智能降级：Microsoft Office → Apple iWork → LibreOffice |
| HTML → PDF | 网页转 PDF | WebKit（WKWebView） |
| 页面操作 | 合并 / 拆分 / 旋转 | PDFKit + qpdf |
| 优化 | PDF 压缩 | Ghostscript |
| 编辑 | 添加水印 | PDFKit |
| 安全 | 加密 / 解密 | qpdf（256-bit AES） |
| OCR | 可搜索 PDF | Tesseract |
| AI | 摘要 / 翻译 / Markdown | DeepSeek Chat API |

## 部署说明

### Docker / 容器化部署说明

本项目目前为 **macOS 原生 GUI 应用**，基于 SwiftUI 及系统框架（PDFKit、AppKit）构建，因此 **暂不提供官方 Docker 容器化部署方案**。主要原因如下：

- 运行依赖 macOS 系统能力与图形界面环境，无法直接运行于通用 Linux 容器中；
- 转换依赖多项系统级工具（LibreOffice、Poppler、qpdf、Ghostscript、Tesseract），当前通过主机本地安装提供，而非内置于应用内部；
- 目前未提供 headless / CLI / Server 运行模式，无可供远程调用的 HTTP API 服务入口。

如有服务化部署需求，后续版本可考虑增加独立的 **Server / CLI 模式**（例如 FastAPI + 后台命令调用），届时将补充 Dockerfile 与部署文档。在此之前，建议仍在 macOS 本地构建运行。

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

## 数据流：从「开始转换」到文件生成

下图展示一次完整的转换流程，涉及 SwiftUI 视图层、ViewModel 层、Core 层引擎层和外部 CLI 工具：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          用户操作（SwiftUI 视图层）                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────┐  拖拽文件   ┌──────────────┐  选类型    ┌──────────────────┐  │
│  │DropZone  │──────────▶│ FileListView │──────────▶│ ConversionPanel  │  │
│  │  View    │           │              │           │      View        │  │
│  └──────────┘           └──────────────┘           └────────┬─────────┘  │
│                                                            │ 点开始        │
│                                                            ▼              │
│  ┌──────────────┐                                  ┌──────────────────┐   │
│  │  Sidebar     │                                  │  Conversion      │   │
│  │  View        │                                  │  Options View    │   │
│  └──────────────┘                                  │ (参数:DPI/密码等) │   │
│                                                    └────────┬─────────┘   │
│                                                             │             │
│  ┌──────────────────────────────────────────────────────────▼──────────┐  │
│  │                       ContentView (主视图)                            │  │
│  └────────────────────────────────────┬─────────────────────────────────┘  │
└─────────────────────────────────────┼────────────────────────────────────┘
                                      │ @EnvironmentObject
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       AppViewModel (@MainActor)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────────────────────────────────────────────────────────┐     │
│   │ @Published inputURLs / selectedType / parameters / jobs           │     │
│   └──────────────────────────────────────────────────────────────────┘     │
│              │                                            ▲                  │
│   enqueueConversion()                              AsyncStream observeJobs()│
│              │                                            │                  │
│              ▼                                            │                  │
│   ┌──────────────────────────────────────────┐            │                  │
│   │  ConversionJob(                           │            │                  │
│   │    type, inputURLs, outputDirectory,      │            │                  │
│   │    parameters                            │            │                  │
│   │  )                                       │            │                  │
│   └────────────────────┬─────────────────────┘            │                  │
│                        │                                  │                  │
│                        │ progressHandler 闭包            │                  │
│                        │ (在 MainActor 上调用)            │                  │
└────────────────────────┼──────────────────────────────────┼──────────────────┘
                         │                                  │
                         ▼                                  │
┌─────────────────────────────────────────────────────────────────────────────┐
│                  JobOrchestrator (actor, Core 层)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   enqueue(job)                                                              │
│      │                                                                      │
│      ▼                                                                      │
│   queue.append(job)  ──── broadcastUpdate() ──────────────────────────────┐  │
│      │                                                                  │  │
│      ▼                                                                  │  │
│   pump()                                                               │  │
│      │  取第一个 pending 任务                                           │  │
│      │  设置 status = .running, progress = 0.05                        │  │
│      │  notify(job)  ────────▶ 触发 UI 更新 ◀───────── AsyncStream ────┘  │
│      ▼                                                                  ▲  │
│   execute(job)                                                         │  │
│      │                                                                  │  │
│      ▼                                                                  │  │
│   ┌──────────────────────────────────────────────────────────────┐    │  │
│   │  EngineRegistry.engine(for: job.type)                        │    │  │
│   │      │                                                       │    │  │
│   │      ▼                                                       │    │  │
│   │  typeIndex: [ConversionType: any ConversionEngine]           │    │  │
│   │  ┌──────────────────────────────────────────────────────┐   │    │  │
│   │  │ .pdfToPNG     → PopplerEngine                        │   │    │  │
│   │  │ .mergePDF     → PDFKitEngine                         │   │    │  │
│   │  │ .wordToPDF    → OfficeAutomationEngine ─┐            │   │    │  │
│   │  │ .ocrPDF       → TesseractEngine          │            │   │    │  │
│   │  │ .pdfAITranslate → AppLLMEngine          │            │   │    │  │
│   │  │ ...                                       │            │   │    │  │
│   │  └──────────────────────────────────────────│────────────┘   │    │  │
│   └─────────────────────────────────────────────│────────────────┘    │  │
│                                                 │                     │  │
│   ┌─────────────────────────────────────────────▼────────────────┐   │  │
│   │  engine.convert(context: ConversionContext)                  │   │  │
│   │  ┌──────────────────────────────────────────────────────────┐│   │  │
│   │  │ context.workDirectory = /tmp/PDFConverter/<job-uuid>/    ││   │  │
│   │  │ context.toolsRoot       = Resources/tools/               ││   │  │
│   │  │ context.job              = ConversionJob                  ││   │  │
│   │  └──────────────────────────────────────────────────────────┘│   │  │
│   └────────────────────────────────┬─────────────────────────────┘   │  │
│                                    │ ConversionResult                 │  │
│                                    │ { outputURLs, logs }              │  │
│                                    ▼                                  │  │
│   设置 status = .completed, progress = 1.0                            │  │
│   notify(job) ─────────▶ 触发 UI 更新 ◀───────── AsyncStream ─────────┘  │
│                                                                            │
│   （整个过程中引擎可调用 updateProgress(id:, progress:) 推送中间进度）   │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                  引擎层（Core/Engines/）                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌────────────────────────────────────┐                                   │
│   │  PDFKitEngine  (macOS 原生框架)     │  pngToPDF / mergePDF / rotatePDF  │
│   │  PDFDocument, PDFPage               │  → 不调用外部 CLI                  │
│   └────────────────────────────────────┘                                   │
│                                                                             │
│   ┌────────────────────────────────────┐                                   │
│   │  PopplerEngine                     │  pdfToPNG / pdfToText            │
│   │  ProcessRunner.runChecked()        │  → pdftoppm / pdftotext         │
│   │      │                             │                                   │
│   │      ▼                             │                                   │
│   │  Process(args: pdftoppm ...)       │                                   │
│   └────────────────────────────────────┘                                   │
│                                                                             │
│   ┌────────────────────────────────────┐                                   │
│   │  OfficeAutomationEngine (智能降级)  │  wordToPDF / pdfToWord            │
│   │  ┌────────────────────────────────┐│                                   │
│   │  │ 1. Microsoft Office (osascript)││                                   │
│   │  │     ↓ 失败                     ││                                   │
│   │  │ 2. Apple iWork (osascript)     ││                                   │
│   │  │     ↓ 失败                     ││                                   │
│   │  │ 3. LibreOffice (soffice --hd)  ││                                   │
│   │  └────────────────────────────────┘│                                   │
│   └────────────────────────────────────┘                                   │
│                                                                             │
│   ┌────────────────────────────────────┐                                   │
│   │  TesseractEngine / Ghostscript /   │  ocrPDF / compressPDF / ...       │
│   │  QpdfEngine / AppWebKitEngine      │  → 对应 CLI 工具                  │
│   └────────────────────────────────────┘                                   │
│                                                                             │
│   ┌────────────────────────────────────┐                                   │
│   │  AppLLMEngine (云端)               │  pdfAISummary / pdfAITranslate   │
│   │  pdftotext → DeepSeek API          │  → HTTPS POST api.deepseek.com   │
│   └────────────────────────────────────┘                                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                  外部依赖层                                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────────────────────┐  ┌────────────────────┐  ┌────────────────┐    │
│  │ macOS PDFKit Framework │  │ Resources/tools/   │  │  系统 PATH      │    │
│  │ (Swift 框架,系统自带)  │  │  ├─ poppler/       │  │  ├─ soffice    │    │
│  └────────────────────────┘  │  ├─ qpdf/          │  │  └─ ...        │    │
│                             │  ├─ ghostscript/   │  └────────────────┘    │
│                             │  ├─ tesseract/     │                          │
│                             │  └─ libreoffice/   │                          │
│                             └────────────────────┘                          │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────┐           │
│  │  Keychain (存储 DeepSeek API Key)                            │           │
│  │  UserDefaults (存储 BaseURL / Model 名称)                    │           │
│  └─────────────────────────────────────────────────────────────┘           │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────┐           │
│  │  DeepSeek API  (https://api.deepseek.com)  仅 AI 功能使用     │           │
│  └─────────────────────────────────────────────────────────────┘           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 关键路径详解

#### 1. 任务创建到入队
```
用户拖拽文件 → DropZoneView 更新 inputURLs
            → 用户选择类型 → SidebarView 更新 selectedType
            → 用户调整参数 → ConversionOptionsView 更新 parameters
            → 用户点「开始转换」→ ContentView 触发 enqueueConversion()
            → AppViewModel 创建 ConversionJob 提交到 JobOrchestrator
```

#### 2. 任务调度与执行
```
JobOrchestrator.pump() 找到第一个 pending 任务
                      设置为 running（progress = 0.05）
                      触发 notify → AppViewModel 更新 jobs[i].progress → UI 立即渲染
                      异步执行 executeJob(job)
                          → EngineRegistry 查找引擎
                          → engine.convert(context) 执行转换
                              → 引擎可调用 JobOrchestrator.updateProgress() 推送中间进度
                          → 收到 ConversionResult，设置 completed / failed
                      notify → UI 更新状态徽章和输出文件链接
                      AsyncStream 推送最新任务列表给所有订阅者
                      重新 pump() 处理下一个任务
```

#### 3. UI 响应（关键解耦）
```
JobOrchestrator 状态变化
   ├─ notify(progressHandler)        ──▶ 闭包更新 jobs 数组（in-place 修改）
   └─ broadcastUpdate(AsyncStream)   ──▶ 推送新快照给所有订阅者

AppViewModel 监听这两条路径：
   - progressHandler 闭包: 即时更新当前正在变化的任务
   - AsyncStream: 兜底推送整张任务表（兜底同步）
两路合并后 SwiftUI 自动重渲染
```

#### 4. 智能降级（OfficeAutomationEngine 专属）
```
用户转换 Word → PDF
   ├─ 检查 com.microsoft.Word 是否安装
   │     └─ 是 → AppleScript 调用 Word 导出 PDF → 完成
   │     └─ 否 ↓
   ├─ 检查 com.apple.iWork.Pages 是否安装
   │     └─ 是 → AppleScript 调用 Pages 导出 PDF → 完成
   │     └─ 否 ↓
   └─ 回退到 LibreOfficeEngine (soffice --headless --convert-to pdf)
         └─ 用户需先安装 LibreOffice（提示信息由 ConversionError.missingTool 提供）
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

### 6. 链式降级引擎（OfficeAutomationEngine）

`OfficeAutomationEngine` 利用 macOS 原生 AppleScript 能力，实现无需捆绑大体积工具的 Office 文档转换：

```
Microsoft Office (AppleScript) → Apple iWork (AppleScript) → LibreOffice (headless)
```

每个后端都独立检测可用性，上游失败时自动降级。这种模式避免了将 ~1.2GB 的 LibreOffice 打包进应用 DMG，同时让装了 Office 或 iWork 的用户获得零额外安装的体验。

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
git tag v0.2.6
git push origin v0.2.6
```

构建流程：安装 Homebrew 依赖 → 打包 CLI 工具 → `xcodebuild build` → 提取 `.app` → 生成 `.dmg` → 上传到 Release。

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

捆绑的 Poppler、qpdf、Ghostscript、Tesseract 等第三方工具请遵循其各自的开源协议。LibreOffice 不包含在 DMG 中；Office 转换引擎会优先尝试系统已有的 Microsoft Office 或 Apple iWork，仅当两者都不可用时才提示安装 LibreOffice。
