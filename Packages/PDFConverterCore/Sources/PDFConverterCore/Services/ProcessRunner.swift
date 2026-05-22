import Foundation

public enum ProcessRunner {
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

            var env = ProcessInfo.processInfo.environment
            environment.forEach { env[$0.key] = $0.value }
            process.environment = env
            process.currentDirectoryURL = currentDirectory

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: (stdout, stderr, proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

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
