import Foundation

/// 异步执行外部命令的工具，是引擎与 CLI 工具之间的桥梁。
///
/// 所有引擎都通过 `ProcessRunner` 来调用外部命令行工具（如 `pdftoppm`、`qpdf`、`gs` 等），
/// 而不是各自封装 `Process` 调用。这样做的目的：
///
/// - **统一错误处理**：所有工具调用的错误都会通过 `processFailed` 统一抛出
/// - **避免死锁**：使用 `readabilityHandler` 实时读取管道数据，而不是等到进程结束后
///   再一次性读取。如果不实时消费管道数据，当输出超过管道缓冲区大小时会导致死锁
/// - **异步封装**：将阻塞式的进程操作封装为 `async throws` 接口，与 Swift 并发模型无缝衔接
///
/// ## 为什么不用 `async/await` 直接包装 `Process`？
/// `Process` 本身不支持 async/await，它的 completion 是回调式的。
/// 这里通过 `withCheckedThrowingContinuation` 将回调桥接到 async/await，
/// 使得引擎可以以同步风格编写异步代码。
public enum ProcessRunner {
    /// 异步执行外部命令，返回完整的 stdout、stderr 和退出码。
    ///
    /// ## 关键设计：readabilityHandler 防死锁
    /// 为什么使用 `readabilityHandler` 而不是 `readDataToEndOfFile()`？
    ///
    /// `readDataToEndOfFile()` 是一个**阻塞**调用——它会一直等待直到管道关闭。
    /// 如果管道缓冲区满了而进程在等待缓冲区被消费，而程序又在等待进程结束再读数据，
    /// 就会进入经典的死锁循环。使用 `readabilityHandler` 可以在数据到达时**实时消费**，
    /// 永远不会阻塞管道，从而避免死锁。
    ///
    /// - Parameters:
    ///   - executable: 可执行文件的 URL
    ///   - arguments: 命令行参数数组（不含程序名本身）
    ///   - environment: 额外的环境变量（会合并到当前进程的环境中）
    ///   - currentDirectory: 子进程的工作目录
    /// - Returns: `(stdout, stderr, exitCode)` 三元组
    /// - Throws: 如果子进程启动失败则抛出错误
    public static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectory: URL? = nil
    ) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            // 合并环境变量：基础是当前进程的环境，用户可以追加或覆盖
            var env = ProcessInfo.processInfo.environment
            environment.forEach { env[$0.key] = $0.value }

            // 将工具所在目录加入 dylib 搜索路径，确保子进程能找到捆绑的动态库
            let execDir = executable.deletingLastPathComponent().path
            if let existing = env["DYLD_FALLBACK_LIBRARY_PATH"] {
                env["DYLD_FALLBACK_LIBRARY_PATH"] = "\(execDir):\(existing)"
            } else {
                env["DYLD_FALLBACK_LIBRARY_PATH"] = "\(execDir):/usr/local/lib:/lib:/usr/lib"
            }

            process.environment = env
            process.currentDirectoryURL = currentDirectory

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutData = NSMutableData()
            let stderrData = NSMutableData()
            let lock = NSLock()

            // readabilityHandler 在有数据到达时被系统调用，实时读取防止缓冲区满导致死锁
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    lock.lock()
                    stdoutData.append(data)
                    lock.unlock()
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    lock.lock()
                    stderrData.append(data)
                    lock.unlock()
                }
            }

            process.terminationHandler = { proc in
                // 进程结束后，先取消 readabilityHandler 防止继续读取
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                // 读取 handler 关闭后管道中剩余的残留数据
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                if !remainingStdout.isEmpty {
                    stdoutData.append(remainingStdout)
                }
                lock.unlock()

                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                if !remainingStderr.isEmpty {
                    stderrData.append(remainingStderr)
                }
                lock.unlock()

                lock.lock()
                let stdout = String(data: stdoutData as Data, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData as Data, encoding: .utf8) ?? ""
                lock.unlock()

                continuation.resume(returning: (stdout, stderr, proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// 执行命令并检查退出码，非零则抛出 `processFailed` 错误。
    ///
    /// 这是引擎中更常用的调用方式——大多数 CLI 工具用退出码来表示成功/失败，
    /// 退出码 0 表示成功，非 0 表示失败。如果失败，错误信息中会包含完整的命令、
    /// 退出码和标准错误输出，方便用户排查。
    ///
    /// - Parameters:
    ///   - executable: 可执行文件 URL
    ///   - arguments: 命令行参数
    ///   - environment: 额外环境变量
    ///   - currentDirectory: 工作目录
    /// - Returns: 标准输出内容（仅退出码 0 时才有意义）
    /// - Throws: 退出码非 0 时抛出 ``ConversionError.processFailed``
    public static func runChecked(
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectory: URL? = nil
    ) async throws -> String {
        let result = try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory
        )
        guard result.exitCode == 0 else {
            throw ConversionError.processFailed(
                command: ([executable.path] + arguments).joined(separator: " "),
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result.stdout
    }
}