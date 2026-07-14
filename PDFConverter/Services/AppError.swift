import Foundation
import SwiftUI

/// 应用错误严重级别。
///
/// 决定 UI 显示样式：
/// - `.info`: 蓝色提示条，自动消失（例如启动工具检测提醒）
/// - `.warning`: 橙色提示条，需要用户操作但不阻塞流程
/// - `.error`: 红色错误条，阻塞当前操作的关键错误
public enum AppErrorSeverity: String, Sendable, Codable {
    case info
    case warning
    case error

    /// 颜色映射
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    /// 图标名
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

/// 应用错误模型。
///
/// 表示一个可被 UI 显示的错误（区别于 `ConversionError` 这种内部错误类型）。
/// `AppError` 关注的是「用户需要知道什么」而不是「技术细节」。
///
/// 与 `ConversionError` 的区别：
/// - `ConversionError`: 引擎层错误，可能很技术化（如 "Process exit 127"）
/// - `AppError`: 用户层错误，已经翻译成可操作的中文消息
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

    // Equatable 仅基于 id（因为 actions 包含不可比较的回调）
    public static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.id == rhs.id
    }
}

/// 错误横幅上的可操作按钮。
///
/// 例如 "打开下载页"、"在 Finder 中显示"、"重试" 等。
public struct AppErrorAction: Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let role: ActionRole
    public let callback: @Sendable () async -> Void

    public enum ActionRole: String, Sendable {
        case primary    // 蓝色强调按钮
        case secondary  // 灰色次要按钮
        case cancel     // 取消/关闭
    }

    public init(
        id: UUID = UUID(),
        label: String,
        role: ActionRole = .secondary,
        callback: @escaping @Sendable () async -> Void
    ) {
        self.id = id
        self.label = label
        self.role = role
        self.callback = callback
    }
}

// MARK: - 预定义的常见错误

extension AppError {
    /// LibreOffice 未安装
    static func missingLibreOffice() -> AppError {
        AppError(
            severity: .warning,
            title: "未检测到 LibreOffice",
            message: "Office 文档（Word/Excel/PPT）转换需要 LibreOffice。\nMicrosoft Office 和 Apple iWork 也可以替代。",
            actions: [
                AppErrorAction(label: "下载 LibreOffice", role: .primary) {
                    if let url = URL(string: "https://www.libreoffice.org/download/") {
                        await MainActor.run {
                            NSWorkspace.shared.open(url)
                        }
                    }
                },
                AppErrorAction(label: "安装指引", role: .secondary) {
                    // 由 AppViewModel 处理（显示详细安装说明 sheet）
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
                AppErrorAction(label: "前往设置", role: .primary) {
                    // 由 AppViewModel 处理（打开设置）
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
                AppErrorAction(label: "查看详情", role: .secondary) {
                    // 由 AppViewModel 处理（打开设置显示工具列表）
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