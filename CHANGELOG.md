# 更新日志

所有对本项目有重大变更的版本都记录于此。格式基于 [Keep a Changelog](https://keepachangelog.com/)。

## [Unreleased]

### 计划中
- 国际化：英文 UI 支持

## [0.4.7] - 2026-07-15

### 性能
- **OfficeAvailability 10 秒缓存**：避免 SwiftUI body 重渲染时重复查 NSWorkspace
- **LogStore 智能订阅**：从 1 秒轮询改为 AsyncStream 订阅，零延迟 + 无新日志零开销
- **AppLogger version 机制**：每次 log() 递增版本号，订阅者可实时感知

### 健壮性
- **TesseractEngine 原子操作**：`replaceItemAt` 替代「先 remove 再 move」，防止中间失败丢文件
- **dependabot.yml**：自动检测 GitHub Actions 和 SwiftPM 依赖更新

### 清理
- 删除 ErrorBanner 中未使用的 `@State showDetail`

## [0.4.6] - 2026-07-15

### 修复
- **AppError 按钮 callback 修复**："安装指引" 和 "前往设置" 按钮点击不再无反应
  - 引入 `AppErrorContext`，把 `callback` 改为 `(AppErrorContext) -> Void`
  - `AppViewModel` 注册三个 handler 真正打开对应 UI
- **删除空函数**：`AppViewModel.clearError()` 已被 ErrorCenter 取代，移除死代码
- **`removeJob` 内存泄漏修复**：从队列移除任务时同步清理 `notifiedJobFailures` 集合
- **`clearCompletedJobs` 同步清理**：清空已完成任务时同步清理通知集合
- **日志防爆**：失败任务的 stderr 截断到 2KB
- **错误 API 重命名**：`missingLibreOffice` → `missingOfficeBackend`（更准确）

### 工程
- **CI 添加单元测试**：`release.yml` 在打包前先跑 `swift test`
- **CHANGELOG.md 创建**：集中记录所有变更

## [0.4.5] - 2026-07-15

### 新增
- **应用日志系统**：os.Logger + 内存缓冲（最近 500 条）
- **应用内日志查看器**：设置页面 → 调试日志 → 查看日志
- **Console.app 集成**：一键打开 macOS 统一日志系统
- **迈阿密海滩风格应用图标**：粉色渐变 + 棕榈树 + 太阳 + PDF 文档
- **README 完善**：新增「系统要求与运行环境」章节

### 修复
- LogStore Swift 6 self capture 编译错误
- project.pbxproj 漏注册新文件到 PBXBuildFile

## [0.4.4] - 2026-07-15

### 新增
- **重置/删除功能补全**：
  - 文件列表：单文件删除按钮、顶部清空全部
  - 参数面板：每类型重置 + 全部重置按钮（含确认对话框）
  - 输出文件夹：清除按钮（恢复默认）
  - 任务队列：单条删除、清空已完成、清空全部
  - 侧边栏：重置为默认类型按钮

## [0.4.3] - 2026-07-15

### 新增
- **完整错误提示系统**：
  - `AppError` 模型：severity + title + message + details + actions
  - `ErrorCenter`：全局错误状态管理（自动去重、5 秒自动消失、保留 50 条历史）
  - `ErrorBannerList`：多层级错误横幅（info/warning/error）
  - 失败任务可点击查看完整 stderr
  - Pre-flight 检查：用户点击转换前先检测后端
  - Office 安装指引 Sheet

## [0.4.2] - 2026-07-15

### 修复
- **进度条不动（致命）**：`AppViewModel.bootstrap` 没有传 progressHandler
- **UI 不自动响应任务状态**：JobOrchestrator 新增 `observeJobs() -> AsyncStream<[ConversionJob]>`
- **ProgressView 完成时消失**：running + completed 都显示
- **Poppler 输出文件名前缀**：用 input stem 而非 `page-N`
- **Tesseract tessdata 路径**：以 `/` 结尾

## [0.4.1] - 2026-07-14

### 修复
- **Office 文档功能可见性**：
  - `ConversionType.isAvailableInMVP` 补全 `pdfToWord/pdfToExcel`
  - `groupedTypes` 始终显示 Office 分类
  - `SidebarView` 显示「需安装」徽章
  - `ConversionOptionsView` 显示安装指引
- **Swift 6 编译错误**：`JobOrchestrator` 之前的 commit 漏了 `var job` 捕获修复

## [0.4.0] - 2026-07-14

### 新增
- **OfficeAutomationEngine**：链式降级转换 Office 文档
  - Microsoft Office → Apple iWork → LibreOffice
  - 通过 AppleScript 调用 Office/iWork，零安装
- **应用图标（基础版）**：10 个 PNG 16-1024px

### 修复
- `LibreOfficeEngine.supportedTypes()` 缺失闭合大括号
- `OfficeAutomationEngine` 缺失 `import AppKit`

## [0.3.x] - 早期版本

参见 [Git history](https://github.com/blackjaxx/PDFConverter/commits/main) 了解 v0.3.x 系列。

---

[Unreleased]: https://github.com/blackjaxx/PDFConverter/compare/v0.4.6...HEAD
[0.4.6]: https://github.com/blackjaxx/PDFConverter/compare/v0.4.5...v0.4.6
[0.4.5]: https://github.com/blackjaxx/PDFConverter/compare/v0.4.4...v0.4.5
[0.4.4]: https://github.com/blackjaxx/PDFConverter/compare/v0.4.3...v0.4.4
[0.4.3]: https://github.com/blackjaxx/PDFConverter/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/blackjaxx/PDFConverter/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/blackjaxx/PDFConverter/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/blackjaxx/PDFConverter/compare/v0.3.22...v0.4.0
