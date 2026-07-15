import Foundation
import Combine

/// 日志存储的 SwiftUI 包装 - 让 SettingsView 能响应日志更新。
///
/// v0.4.7 升级：从 1 秒轮询改为基于 AppLogger 版本号的智能订阅：
/// - AppLogger 每次 log() 调用都递增 version
/// - LogStore 用 AsyncStream 订阅 version 变化（零延迟）
/// - 无新日志时零开销（不轮询、不渲染）
@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [AppLogger.LogEntry] = []
    private var lastVersion: UInt64 = 0
    private var subscriptionTask: Task<Void, Never>?

    private init() {
        // 启动时拉取一次
        refresh()

        // 订阅 AppLogger 的版本号变化（零延迟，无新日志时零开销）
        subscriptionTask = Task { [weak self] in
            for await version in AppLogger.shared.versionStream {
                guard let self else { return }
                if version != self.lastVersion {
                    self.refresh()
                }
            }
        }
    }

    func refresh() {
        let snapshot = AppLogger.shared.snapshot()
        // 用 version 比较而非 count，避免时间精度问题
        if snapshot.version != lastVersion {
            entries = snapshot.entries
            lastVersion = snapshot.version
        }
    }

    func clear() {
        AppLogger.shared.clearBuffer()
        entries = []
        lastVersion = 0
    }
}
