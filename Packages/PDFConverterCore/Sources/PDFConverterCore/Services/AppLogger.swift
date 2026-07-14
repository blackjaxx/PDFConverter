import Foundation
import os

/// Core 层的日志服务（精简版，不含 UI 集成）。
///
/// 与 App 层的 AppLogger 区别：
/// - Core 不能 import AppKit（Core 是纯 Swift Package，无 UI 依赖）
/// - Core 版本只提供 os.Logger 输出 + 内存缓冲，不提供剪贴板/Finder 等 UI 集成
///
/// JobOrchestrator 等 Core 层代码使用此版本。
/// App 层代码可以使用增强版 AppLogger（继承相同 API）。
public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()

    public let logger = os.Logger(subsystem: "com.local.pdfconverter", category: "general")

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
    }

    private init() {}

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

        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }

        bufferLock.lock()
        buffer.append(entry)
        if buffer.count > bufferSize {
            buffer.removeFirst(buffer.count - bufferSize)
        }
        bufferLock.unlock()
    }

    public func allEntries() -> [LogEntry] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return buffer
    }

    public func clearBuffer() {
        bufferLock.lock()
        buffer.removeAll()
        bufferLock.unlock()
    }
}