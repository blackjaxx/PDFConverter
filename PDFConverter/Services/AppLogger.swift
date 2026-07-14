import Foundation
import os
import AppKit

/// 全局日志服务 - 包装 os.Logger + 内存缓冲区。
///
/// 为什么需要这个：
/// - SwiftUI 应用默认不写日志到 stdout，用户无法通过 Console.app 查看
/// - os.Logger 是 macOS 13+ 推荐的日志系统，统一通过 Console.app 可读
/// - 内存缓冲区保存最近 N 条日志，方便在 App 内查看（设置页面「查看日志」）
///
/// 使用示例：
/// ```swift
/// AppLogger.shared.info("PDF converted", metadata: ["file": "report.pdf"])
/// AppLogger.shared.error("Process failed", metadata: ["stderr": stderr])
/// ```
public final class AppLogger: @unchecked Sendable {
    /// 全局共享实例
    public static let shared = AppLogger()

    /// os.Logger 实例（subsystem 用于 Console.app 过滤）
    public let logger = Logger(subsystem: "com.local.pdfconverter", category: "general")

    /// 内存日志缓冲区（最近 N 条）
    private let bufferSize = 500
    private let bufferLock = NSLock()
    private var buffer: [LogEntry] = []

    public struct LogEntry: Identifiable, Sendable {
        public let id = UUID()
        public let timestamp: Date
        public let level: LogLevel
        public let message: String
        public let metadata: [String: String]

        public enum LogLevel: String, Sendable {
            case debug, info, warning, error
        }

        public var icon: String {
            switch level {
            case .debug: return "ladybug"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }

        public var color: String {
            switch level {
            case .debug: return "gray"
            case .info: return "blue"
            case .warning: return "orange"
            case .error: return "red"
            }
        }
    }

    private init() {}

    // MARK: - 记录方法

    public func debug(_ message: String, metadata: [String: String] = [:]) {
        log(.debug, message: message, metadata: metadata)
    }

    public func info(_ message: String, metadata: [String: String] = [:]) {
        log(.info, message: message, metadata: metadata)
    }

    public func warning(_ message: String, metadata: [String: String] = [:]) {
        log(.warning, message: message, metadata: metadata)
    }

    public func error(_ message: String, metadata: [String: String] = [:]) {
        log(.error, message: message, metadata: metadata)
    }

    private func log(_ level: LogEntry.LogLevel, message: String, metadata: [String: String]) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message, metadata: metadata)

        // 1. 写入 os.Logger（可通过 Console.app / `log show` 查看）
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }

        // 2. 写入内存缓冲区（设置页面用）
        bufferLock.lock()
        buffer.append(entry)
        if buffer.count > bufferSize {
            buffer.removeFirst(buffer.count - bufferSize)
        }
        bufferLock.unlock()
    }

    // MARK: - 查询方法

    /// 获取所有缓冲区日志（最新的在最后）
    public func allEntries() -> [LogEntry] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return buffer
    }

    /// 清空缓冲区
    public func clearBuffer() {
        bufferLock.lock()
        buffer.removeAll()
        bufferLock.unlock()
    }

    /// 导出为字符串（用于「保存日志」功能）
    public func exportAsString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return buffer.map { entry in
            let meta = entry.metadata.isEmpty ? "" : " \(entry.metadata)"
            return "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue.uppercased())] \(entry.message)\(meta)"
        }.joined(separator: "\n")
    }

    /// 用 Finder 显示日志文件
    public func revealLogFileInFinder() {
        // macOS 统一日志系统路径
        let logDir = URL(fileURLWithPath: "/var/log/DiagnosticMessages")
        if FileManager.default.fileExists(atPath: logDir.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logDir])
        } else {
            // Fallback: 提示用户用 Console.app
            if let url = URL(string: "file:///Applications/Utilities/Console.app") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}