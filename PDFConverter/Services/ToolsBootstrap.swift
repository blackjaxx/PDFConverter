import Foundation

/// 工具引导器，负责在 App Bundle 内查找 CLI 工具的存放路径。
///
/// PDF Converter 将 Poppler、Ghostscript、Qpdf、LibreOffice、Tesseract 等
/// 命令行工具打包在 App Bundle 的 `Contents/Resources/tools/` 目录下。
/// 这样做的好处是：
/// - **零网络依赖**：安装 App 即拥所有工具，无需用户通过 Homebrew 等额外安装
/// - **版本锁定**：App 使用固定版本的工具，避免系统环境差异导致的不兼容
/// - **即开即用**：用户下载 App 后无需任何配置即可直接使用
///
/// 如果 Bundle 内找不到 `tools` 目录，`JobOrchestrator` 会回退到系统 PATH
/// 搜索（允许高级用户通过 Homebrew 安装的工具也能被检测到）。
enum ToolsBootstrap {
    /// 返回 `PDFConverter.app/Contents/Resources/tools` 的 URL。
    ///
    /// `Bundle.main.resourceURL` 指向的就是 `Contents/Resources/` 目录，
    /// 所以只需要追加 `tools` 子目录即可。
    ///
    /// 返回 nil 只有当：
    /// - `resourceURL` 为 nil（理论上不会发生）
    /// - `tools` 目录不存在
    static func toolsRootURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let tools = resourceURL.appendingPathComponent("tools", isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: tools.path, isDirectory: &isDir), isDir.boolValue {
            return tools
        }
        return nil
    }
}