import Foundation
import SwiftUI

/// 应用错误严重级别。
public enum AppErrorSeverity: String, Sendable, Codable {
    case info
    case warning
    case error

    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

/// 错误动作上下文 - 包含 UI 层可以使用的工具。
///
/// v0.4.6 新增：解决「按钮 callback 为空」的问题。
/// 之前 `AppErrorAction` 的 callback 闭包是 `@Sendable () async -> Void`，
/// 没有任何外部信息可以访问，所以「安装指引」「前往设置」按钮只能空实现。
///
/// 现在 callback 接收一个 `AppErrorContext`，可以调用其中提供的方法：
/// - `openURL(_:)`：打开外部链接
/// - `showOfficeInstallGuide()`：弹出 Office 安装指引
/// - `openSettings()`：打开设置窗口
@MainActor
public final class AppErrorContext {
    public static let shared = AppErrorContext()

    /// 标记某类动作的处理已经被 UI 接管
    public var officeInstallHandler: (() -> Void)?
    public var openSettingsHandler: (() -> Void)?
    public var showToolsHandler: (() -> Void)?

    private init() {}

    /// 打开外部 URL（包装 NSWorkspace.open）
    public func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// 让 UI 弹出 Office 安装指引
    public func showOfficeInstallGuide() {
        officeInstallHandler?()
    }

    /// 让 UI 打开设置窗口
    public func openSettings() {
        openSettingsHandler?()
    }

    /// 让 UI 展示工具状态详情
    public func showTools() {
        showToolsHandler?()
    }
}

/// 应用错误模型。
public struct AppError: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let severity: AppErrorSeverity
    public let title: String
    public let message: String
    public let details: String?  // 完整 stderr 等
    public let actions: [AppErrorAction]
    public let timestamp: Date
    public var isSticky: Bool  // 是否需要用户主动关闭（false 则自动消失）

    public init(
        id: UUID = UUID(),
        severity: AppErrorSeverity,
        title: String,
        message: String,
        details: String? = nil,
        actions: [AppErrorAction] = [],
        isSticky: Bool = false
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.details = details
        self.actions = actions
        self.timestamp = Date()
        self.isSticky = isSticky
    }

    // Equatable 仅基于 id（actions 包含不可比较的回调）
    public static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.id == rhs.id
    }

    /// 用于错误去重的「内容指纹」：忽略 id 和 timestamp。
    public var dedupeKey: String {
        "\(severity.rawValue)|\(title)|\(message)"
    }
}

/// 错误横幅上的可操作按钮。
public struct AppErrorAction: Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let role: ActionRole
    public let callback: @Sendable @MainActor (AppErrorContext) async -> Void

    public enum ActionRole: String, Sendable {
        case primary    // 蓝色强调按钮
        case secondary  // 灰色次要按钮
        case cancel     // 取消/关闭
    }

    public init(
        id: UUID = UUID(),
        label: String,
        role: ActionRole = .secondary,
        callback: @escaping @Sendable @MainActor (AppErrorContext) async -> Void
    ) {
        self.id = id
        self.label = label
        self.role = role
        self.callback = callback
    }
}

// MARK: - 预定义的常见错误

extension AppError {
    /// Office 转换后端不可用
    static func missingOfficeBackend() -> AppError {
        AppError(
            severity: .warning,
            title: "未检测到 Office 转换后端",
            message: "Office 文档（Word/Excel/PPT）转换需要：\n• Microsoft Office 365\n• Apple iWork（Pages/Numbers/Keynote）\n• 或 LibreOffice（免费）",
            actions: [
                AppErrorAction(label: "下载 LibreOffice", role: .primary) { ctx in
                    if let url = URL(string: "https://www.libreoffice.org/download/") {
                        ctx.openURL(url)
                    }
                },
                AppErrorAction(label: "安装指引", role: .secondary) { ctx in
                    ctx.showOfficeInstallGuide()
                }
            ],
            isSticky: true
        )
    }

    /// DeepSeek 未配置（用户点了 AI 转换）
    static func deepSeekNotConfigured() -> AppError {
        AppError(
            severity: .warning,
            title: "DeepSeek 未配置",
            message: "AI 功能需要 DeepSeek API Key。\n前往「设置 → DeepSeek」填写。",
            actions: [
                AppErrorAction(label: "前往设置", role: .primary) { ctx in
                    ctx.openSettings()
                }
            ],
            isSticky: true
        )
    }

    /// CLI 工具启动时缺失
    static func missingCriticalTools(_ names: [String]) -> AppError {
        AppError(
            severity: .warning,
            title: "部分工具未安装",
            message: "以下 CLI 工具未检测到：\(names.joined(separator: "、"))\n相关功能将无法使用。",
            actions: [
                AppErrorAction(label: "查看详情", role: .secondary) { ctx in
                    ctx.showTools()
                }
            ],
            isSticky: false
        )
    }

    /// 任务失败（来自 JobOrchestrator 的错误通知）
    static func jobFailed(jobType: String, error: String, details: String? = nil) -> AppError {
        AppError(
            severity: .error,
            title: "\(jobType) 转换失败",
            message: error,
            details: details
        )
    }

    /// 文件读取失败
    static func fileReadFailed(path: String, error: String) -> AppError {
        AppError(
            severity: .error,
            title: "无法读取文件",
            message: path,
            details: error
        )
    }

    /// 网络错误
    static func networkError(_ message: String) -> AppError {
        AppError(
            severity: .error,
            title: "网络错误",
            message: message
        )
    }
}