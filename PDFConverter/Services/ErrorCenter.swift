import Foundation
import SwiftUI

/// 错误中心 - 全局错误状态管理。
///
/// 类似 `NotificationCenter` 但专门管理用户可见的错误：
/// - AppViewModel 持有 `ErrorCenter.shared`
/// - 任何位置通过 `errorCenter.report(...)` 推送错误
/// - UI 监听 `errors` 数组自动显示横幅
///
/// 设计要点：
/// - **单例模式**：全局共享，任意位置可访问
/// - **自动消失**：非 sticky 错误 5 秒后自动移除
/// - **去重**：相同错误（基于 title + message）不会重复显示
/// - **MainActor 隔离**：保证线程安全 + UI 更新
@MainActor
final class ErrorCenter: ObservableObject {
    /// 全局共享实例
    static let shared = ErrorCenter()

    /// 当前活动错误列表（最多保留 5 个）
    @Published private(set) var errors: [AppError] = []
    /// 完整错误历史（保留最近 50 个，用于「查看所有错误」）
    @Published private(set) var history: [AppError] = []
    /// 当前展开详情的错误（点击查看完整 stderr 时）
    @Published var detailError: AppError?

    private let maxActiveErrors = 5
    private let maxHistorySize = 50
    private let autoDismissAfter: TimeInterval = 5.0
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    // MARK: - 报告错误

    /// 推送一个错误到 UI。
    /// - Parameters:
    ///   - error: 要显示的错误
    ///   - autoDismiss: 是否在显示后自动消失（覆盖错误自身的 isSticky 设置）
    func report(_ error: AppError, autoDismiss: Bool? = nil) {
        // 去重：如果完全相同的错误已经在显示，不重复添加
        if errors.contains(where: { $0.title == error.title && $0.message == error.message }) {
            return
        }

        // 限制活动错误数量（FIFO）
        if errors.count >= maxActiveErrors, let oldest = errors.first {
            remove(id: oldest.id)
        }

        errors.append(error)
        history.append(error)

        // 限制历史大小
        if history.count > maxHistorySize {
            history.removeFirst(history.count - maxHistorySize)
        }

        // 决定是否自动消失
        let shouldAutoDismiss = autoDismiss ?? (!error.isSticky && error.actions.isEmpty)
        if shouldAutoDismiss {
            scheduleAutoDismiss(error.id)
        }
    }

    /// 便捷方法：用 severity + message 快速创建并显示错误
    func reportError(title: String, message: String, details: String? = nil, severity: AppErrorSeverity = .error) {
        let error = AppError(
            severity: severity,
            title: title,
            message: message,
            details: details
        )
        report(error)
    }

    /// 便捷方法：显示信息提示（蓝色，自动消失）
    func reportInfo(_ message: String) {
        let error = AppError(
            severity: .info,
            title: "提示",
            message: message
        )
        report(error)
    }

    // MARK: - 移除错误

    /// 用户主动关闭某个错误
    func remove(id: UUID) {
        errors.removeAll { $0.id == id }
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
    }

    /// 清除所有错误（设置页面的「清除通知」按钮用）
    func clearAll() {
        for task in dismissTasks.values { task.cancel() }
        dismissTasks.removeAll()
        errors.removeAll()
    }

    /// 清除历史记录
    func clearHistory() {
        history.removeAll()
    }

    // MARK: - 详情查看

    /// 打开错误详情面板
    func showDetail(_ error: AppError) {
        detailError = error
    }

    /// 关闭错误详情面板
    func dismissDetail() {
        detailError = nil
    }

    // MARK: - 内部

    private func scheduleAutoDismiss(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(5_000_000_000))
            if !Task.isCancelled {
                self?.remove(id: id)
            }
        }
    }
}