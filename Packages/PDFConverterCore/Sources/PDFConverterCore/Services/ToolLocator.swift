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
    ///    - 注意：仅当工具能真正执行（`canExecute()` 返回 true）时才认为可用
    ///    - 否则把坏路径加入黑名单，跳到下一步
    /// 3. 最后查找系统 PATH（通过 `findOnPATH` 搜索每个路径）
    ///
    /// 找到的路径会写入缓存，后续调用直接命中缓存。
    ///
    /// v0.4.8 修复：之前的版本只用 `isExecutableFile` 检查文件存在 + 执行位，
    /// 但 dyld 加载失败的工具也会通过校验，导致 ProcessRunner 启动后挂掉。
    /// 现在实际跑一下 `--version`/`-v` 来确认工具能真正执行。
    ///
    /// - Parameters:
    ///   - tool: 要查找的工具描述（包含名称和相对路径）
    ///   - allowSystemFallback: 是否允许回退到系统 PATH，默认 `true`
    /// - Returns: 工具的可执行文件绝对路径，找不到则返回 `nil`
    public func path(for tool: BundledTool, allowSystemFallback: Bool = true) -> URL? {
        lock.withLock {
            // 缓存命中：直接返回已查到过的路径（运行时也会验证可用）
            if let cached = cache[tool.name] {
                return cached
            }

            // 优先查找 App 内捆绑的工具——但必须真的能执行
            if let root = toolsRoot {
                let bundled = root.appendingPathComponent(tool.relativePath)
                if FileManager.default.isExecutableFile(atPath: bundled.path), canExecute(bundled) {
                    cache[tool.name] = bundled
                    return bundled
                } else {
                    // 把坏路径加入黑名单（避免重复尝试）
                    blacklisted.insert(tool.name)
                }
            }

            // App 内工具不可用 → 回退到系统 PATH
            if allowSystemFallback, let system = findOnPATH(tool.name), canExecute(system) {
                cache[tool.name] = system
                return system
            }

            return nil
        }
    }

    /// 黑名单：捆绑工具路径不可用的工具名，避免下次继续尝试
    private var blacklisted: Set<String> = []

    /// 真正执行 `--version` 测试能否启动（解决 dyld 加载失败被漏检的 bug）。
    /// 同步执行，开销 <50ms（每个工具只跑一次，缓存命中后不再调用）。
    private func canExecute(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        let stderr = Pipe()
        let stdout = Pipe()
        process.standardError = stderr
        process.standardOutput = stdout

        do {
            try process.run()
        } catch {
            return false
        }

        // 等待最多 3 秒（大多数工具 <100ms 返回）
        process.waitUntilExit()

        return process.terminationReason == .exit && process.terminationStatus == 0
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

    /// 遍历 PATH 环境变量 + 常见 Homebrew 路径，查找可执行文件。
    ///
    /// v0.4.8 改进：除了默认的 PATH，还补充 macOS 上工具常见的安装位置。
    /// 优先级：
    /// 1. 进程的 PATH 环境变量
    /// 2. Homebrew on Apple Silicon: `/opt/homebrew/bin`
    /// 3. Homebrew on Intel: `/usr/local/bin`
    /// 4. 系统路径: `/usr/bin`、`/bin`
    ///
    /// - Parameter name: 要查找的可执行文件名
    /// - Returns: 找到的可执行文件路径，未找到返回 `nil`
    private func findOnPATH(_ name: String) -> URL? {
        // v0.4.8：合并 PATH + 常见 brew 路径（即使 PATH 中没有 brew）
        var searchDirs: [String] = []
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            searchDirs.append(contentsOf: pathEnv.split(separator: ":").map(String.init))
        }
        // 补充 brew 常见路径（即使 PATH 没设）
        for brewDir in ["/opt/homebrew/bin", "/opt/homebrew/sbin",
                        "/usr/local/bin", "/usr/local/sbin",
                        "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            if !searchDirs.contains(brewDir) {
                searchDirs.append(brewDir)
            }
        }

        for dir in searchDirs {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// 安装提示：返回缺失的关键工具的 brew 安装命令。
    /// 用于 App 启动时提示用户安装缺失的工具。
    static func installHint(forMissing tools: [String]) -> String {
        var brewFormulae = Set<String>()
        for tool in tools {
            switch tool {
            case "pdftoppm", "pdftotext":
                brewFormulae.insert("poppler")
            case "qpdf":
                brewFormulae.insert("qpdf")
            case "gs":
                brewFormulae.insert("ghostscript")
            case "tesseract":
                brewFormulae.insert("tesseract")
            case "soffice":
                brewFormulae.insert("--cask libreoffice")
            default:
                break
            }
        }
        if brewFormulae.isEmpty { return "" }
        return "brew install " + brewFormulae.sorted().joined(separator: " ")
    }
}