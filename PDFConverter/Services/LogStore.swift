import Foundation
import Combine

/// 日志存储的 SwiftUI 包装 - 让 SettingsView 能响应日志更新。
///
/// 设计：
/// - AppLogger 是单例，内部使用 NSLock 保护 buffer
/// - LogStore 是 ObservableObject，定时（每 1 秒）轮询 buffer 数量变化
/// - SwiftUI 视图通过 @ObservedObject 订阅 LogStore，自动重渲染
@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [AppLogger.LogEntry] = []
    private var lastCount: Int = 0

    private init() {
        // 启动时拉取一次
        refresh()

        // 定时刷新（每 1 秒）
        // 用 Timer 兼容旧 API，新代码可以改用 AsyncTimer 或 CADisplayLink
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer 回调不在 actor 上，需要 hop 到主线程
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        // 保持 timer 引用
        self.refreshTimer = timer
    }

    private var refreshTimer: Timer?


    func refresh() {
        let current = AppLogger.shared.allEntries()
        // 只在数量变化时更新（避免无谓的 SwiftUI 重渲染）
        if current.count != lastCount {
            entries = current
            lastCount = current.count
        }
    }

    func clear() {
        AppLogger.shared.clearBuffer()
        entries = []
        lastCount = 0
    }
}