import Foundation

/// Resolves bundled CLI binaries (non–App Store build: tools live in app Resources/tools).
public final class ToolLocator: @unchecked Sendable {
    public static let shared = ToolLocator()

    private var toolsRoot: URL?
    private var cache: [String: URL] = [:]
    private let lock = NSLock()

    private init() {}

    public func configure(toolsRoot: URL?) {
        lock.lock()
        defer { lock.unlock() }
        self.toolsRoot = toolsRoot
        cache.removeAll()
    }

    public func path(for tool: BundledTool, allowSystemFallback: Bool = true) -> URL? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[tool.name] {
            return cached
        }

        if let root = toolsRoot {
            let bundled = root.appendingPathComponent(tool.relativePath)
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                cache[tool.name] = bundled
                return bundled
            }
        }

        if allowSystemFallback, let system = findOnPATH(tool.name) {
            cache[tool.name] = system
            return system
        }

        return nil
    }

    public func require(_ tool: BundledTool) throws -> URL {
        guard let url = path(for: tool) else {
            throw ConversionError.missingTool(tool.name)
        }
        return url
    }

    public func availabilityReport() -> [(tool: BundledTool, available: Bool, path: String?)] {
        BundledToolsCatalog.all.map { tool in
            let url = path(for: tool, allowSystemFallback: true)
            return (tool, url != nil, url?.path)
        }
    }

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
