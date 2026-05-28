import Foundation
import os

/// 捆绑 CLI 工具的定位器，负责任何外部命令行工具的查找和缓存。
///
/// 查找策略（按优先级排序）：
/// 1. **缓存命中**：如果之前已经查到过，直接返回缓存的路径
/// 2. **App 内捆绑**：在 `Resources/tools/<engine>/` 目录下查找工具，这是最可靠的方式
/// 3. **系统 PATH 回退**：如果 App 内没有捆绑，则搜索系统 PATH 环境变量中的路径
///
/// 为什么需要三级查找？
/// - **缓存的目的是避免重复文件系统 I/O**：每次调用都检查文件是否存在会导致不必要的性能开销
/// - **App 内捆绑优先**：保证使用已知版本的工具，避免系统环境差异导致的行为不一致
/// - **PATH 回退**：开发和调试阶段可能没有打包工具，直接从系统路径调用更方便
///
/// ## 线程安全
/// 使用 `OSAllocatedUnfairLock` 保护 `cache` 字典，因为多个引擎可能并发查询工具路径。
/// 注意 `@unchecked Sendable` 是必需的，因为编译器无法自动推断 `OSAllocatedUnfairLock` 的 Sendable 一致性。
public final class ToolLocator: @unchecked Sendable {
    /// 全局共享实例
    public static let shared = ToolLocator()

    /// 使用 `OSAllocatedUnfairLock` 保护共享可变状态
    private let lock = OSAllocatedUnfairLock()
    /// 工具集的根目录（通常是 `Resources/tools`）
    private var toolsRoot: URL?
    /// 工具名称到绝对路径的缓存（`"pdftoppm" → "/path/to/pdftoppm"`）
    private var cache: [String: URL] = [:]

    private init() {}

    /// 设置工具集的根目录并清空缓存。
    ///
    /// 在 ``JobOrchestrator.configure`` 中调用。因为工具目录变化意味着所有
    /// 之前的缓存路径都可能失效，所以必须清空缓存重新查找。
    ///
    /// - Parameter toolsRoot: 新的工具集根目录，nil 表示仅使用系统 PATH
    public func configure(toolsRoot: URL?) {
        lock.withLock {
            self.toolsRoot = toolsRoot
            cache.removeAll()
        }
    }

    /// 查找指定工具的可执行文件路径。
    ///
    /// 查找流程：
    /// 1. 先查缓存（有锁保护的 O(1) 字典查询）
    /// 2. 再查 App 内打包的目录（`toolsRoot/relativePath`）
    /// 3. 最后查找系统 PATH（通过 `findOnPATH` 搜索每个路径）
    ///
    /// 找到的路径会写入缓存，后续调用直接命中缓存。
    ///
    /// - Parameters:
    ///   - tool: 要查找的工具描述（包含名称和相对路径）
    ///   - allowSystemFallback: 是否允许回退到系统 PATH，默认 `true`
    /// - Returns: 工具的可执行文件绝对路径，找不到则返回 `nil`
    public func path(for tool: BundledTool, allowSystemFallback: Bool = true) -> URL? {
        lock.withLock {
            // 缓存命中：直接返回已查到过的路径
            if let cached = cache[tool.name] {
                return cached
            }

            // 优先查找 App 内捆绑的工具
            if let root = toolsRoot {
                let bundled = root.appendingPathComponent(tool.relativePath)
                if FileManager.default.isExecutableFile(atPath: bundled.path) {
                    cache[tool.name] = bundled
                    return bundled
                }
            }

            // 回退到系统 PATH
            if allowSystemFallback, let system = findOnPATH(tool.name) {
                cache[tool.name] = system
                return system
            }

            return nil
        }
    }

    /// 查找工具，找不到则抛出 ``ConversionError.missingTool`` 错误。
    ///
    /// 这是引擎中最常用的调用方式——因为缺少工具意味着转换无法进行，
    /// 直接抛出错误比返回 nil 再手动处理更简洁。
    ///
    /// - Parameter tool: 要查找的工具
    /// - Returns: 工具的可执行文件绝对路径
    /// - Throws: 工具未找到时抛出 `missingTool` 错误
    public func require(_ tool: BundledTool) throws -> URL {
        guard let url = path(for: tool) else {
            throw ConversionError.missingTool(tool.name)
        }
        return url
    }

    /// 生成所有捆绑工具的可用性报告，用于设置页面的工具状态展示。
    ///
    /// 返回每个工具的名称、是否可用、具体路径这三个信息，
    /// UI 层可以根据 `available` 字段显示绿色/红色状态指示灯。
    ///
    /// - Returns: 每个工具的可用性元组数组
    public func availabilityReport() -> [(tool: BundledTool, available: Bool, path: String?)] {
        BundledToolsCatalog.all.map { tool in
            let url = path(for: tool, allowSystemFallback: true)
            return (tool, url != nil, url?.path)
        }
    }

    /// 遍历 PATH 环境变量，查找可执行文件。
    ///
    /// PATH 按 `:` 分隔，依次检查每个目录下是否存在该名称的可执行文件。
    /// 默认 PATH 值为 `/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin`，
    /// 覆盖了 macOS 常见的工具安装位置。
    ///
    /// - Parameter name: 要查找的可执行文件名
    /// - Returns: 找到的可执行文件路径，未找到返回 `nil`
    private func findOnPATH(_ name: String) -> URL? {
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        for dir in pathEnv.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}